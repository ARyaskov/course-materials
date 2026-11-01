// Waybill.Simulator — нагрузка на API/базу с клиентской стороны (глава 12).
//   dotnet run --project src/Waybill.Simulator -- --mode webhooks --workers 8 --seconds 30 --api http://localhost:5080
//   dotnet run --project src/Waybill.Simulator -- --mode tvp --workers 4 --seconds 20         # напрямую в базу через TVP
//   dotnet run --project src/Waybill.Simulator -- --mode hot --workers 8 --seconds 20         # все воркеры — одно отправление (глава 8)
// Печатает пропускную способность, распределение задержек, ошибки по номерам и ожидания сессий (sys.dm_exec_session_wait_stats).
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Waybill.Data;
using Waybill.Data.Repositories;

var opt = SimOptions.Parse(args);
var factory = new SqlConnectionFactory(Options.Create(new WaybillDbOptions { ConnectionString = opt.Connection, ApplicationName = "Waybill.Simulator" }), NullLogger<SqlConnectionFactory>.Instance);
var ingest = new IngestRepository(factory);
using var http = new HttpClient { BaseAddress = new Uri(opt.Api), Timeout = TimeSpan.FromSeconds(30) };
JsonParameters.Register();

// Пул трек-номеров: сгенерированные отправления FASTEX (глава 9/10) или одно горячее
var trackings = opt.Mode == "hot"
    ? new[] { "FX0000000001" }
    : (await LoadTrackingsAsync(factory, 2000)).ToArray();
Console.WriteLine($"mode={opt.Mode} workers={opt.Workers} seconds={opt.Seconds} trackings={trackings.Length} batch={opt.BatchSize}");

var latencies = new ConcurrentBag<double>();
var errors = new ConcurrentDictionary<string, int>();
long events = 0, calls = 0;
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(opt.Seconds));
var sw = Stopwatch.StartNew();

var workers = Enumerable.Range(0, opt.Workers).Select(w => Task.Run(async () =>
{
    var rnd = new Random(1000 + w);
    var batchNo = 0;
    while (!cts.IsCancellationRequested)
    {
        batchNo++;
        var batch = MakeBatch(trackings, rnd, w, batchNo, opt.BatchSize);
        var t0 = Stopwatch.GetTimestamp();
        try
        {
            switch (opt.Mode)
            {
                case "webhooks":
                    var body = JsonSerializer.Serialize(batch.Select(e => new { eventId = e.ExternalEventId, trackingNumber = e.TrackingNumber, status = e.ExternalStatus,
                        occurredAt = e.OccurredAtUtc.ToString("O"), location = new { text = e.LocationText, postalCode = e.LocationPostalCode }, description = e.Description }));
                    using (var resp = await http.PostAsync("/webhooks/fastex", new StringContent(body, System.Text.Encoding.UTF8, "application/json"), cts.Token))
                        if (!resp.IsSuccessStatusCode) errors.AddOrUpdate($"http {(int)resp.StatusCode}", 1, (_, c) => c + 1);
                    break;
                case "api-tvp":
                    using (var resp = await http.PostAsJsonAsync("/carriers/fastex/events", batch, cts.Token))
                        if (!resp.IsSuccessStatusCode) errors.AddOrUpdate($"http {(int)resp.StatusCode}", 1, (_, c) => c + 1);
                    break;
                default: // tvp | hot — напрямую в базу
                    await Resilience.RetryOnDeadlockAsync(token => ingest.IngestAsync("FASTEX", batch, token), NullLogger.Instance, ct: cts.Token);
                    break;
            }
            Interlocked.Add(ref events, batch.Count);
            Interlocked.Increment(ref calls);
            latencies.Add(Stopwatch.GetElapsedTime(t0).TotalMilliseconds);
        }
        catch (OperationCanceledException) { }
        catch (SqlException) when (cts.IsCancellationRequested) { }          // отмена в момент передачи TVP приходит как «severe error» / «cancelled by user» — не ошибка
        catch (SqlException ex) { var first = ex.Message.Split(Environment.NewLine)[0]; errors.AddOrUpdate($"sql {ex.Number}: {first[..Math.Min(90, first.Length)]}", 1, (_, c) => c + 1); }
        catch (HttpRequestException ex) { errors.AddOrUpdate($"http {ex.Message}", 1, (_, c) => c + 1); }
    }
})).ToArray();

await Task.WhenAll(workers);
sw.Stop();

var sorted = latencies.OrderBy(x => x).ToArray();
double P(double q) => sorted.Length == 0 ? 0 : sorted[(int)Math.Min(sorted.Length - 1, Math.Floor(q * sorted.Length))];
Console.WriteLine($"calls={calls} events={events} elapsed={sw.Elapsed.TotalSeconds:F1}s → {events / sw.Elapsed.TotalSeconds:F0} events/s, {calls / sw.Elapsed.TotalSeconds:F1} calls/s");
Console.WriteLine($"latency ms: p50={P(0.5):F1} p95={P(0.95):F1} p99={P(0.99):F1} max={(sorted.Length == 0 ? 0 : sorted[^1]):F1}");
foreach (var (k, v) in errors.OrderByDescending(kv => kv.Value)) Console.WriteLine($"error {k}: {v}");

// Профиль ожиданий одного вызова: своё соединение, DMV до закрытия
await using (var conn = await factory.OpenAsync())
{
    await ingest.IngestAsync("FASTEX", MakeBatch(trackings, new Random(7), 99, 1, opt.BatchSize), CancellationToken.None);
    var waits = await conn.QueryAsync<(string wait_type, long waiting_tasks_count, long wait_time_ms)>(
        "SELECT wait_type, waiting_tasks_count, wait_time_ms FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID AND wait_time_ms > 0 ORDER BY wait_time_ms DESC");
    Console.WriteLine("session waits (probe call): " + string.Join(", ", waits.Take(5).Select(w => $"{w.wait_type}={w.wait_time_ms}ms")));
}

if (opt.Cleanup)
{
    await using var conn = await factory.OpenAsync();
    var n = await conn.ExecuteAsync("DELETE FROM ship.TrackingEvent WHERE ExternalEventId LIKE 'sim-%'; DELETE FROM ops.Outbox WHERE CAST(Payload AS nvarchar(max)) LIKE '%sim-%' AND ProcessedAt IS NULL;", commandTimeout: 300);
    Console.WriteLine($"cleanup: {n} rows");
}
return 0;

static List<TrackingEventIn> MakeBatch(string[] trackings, Random rnd, int worker, int batchNo, int size)
{
    var statuses = new[] { "IN_TRANSIT", "AT_HUB", "OUT_FOR_DELIVERY" };
    var list = new List<TrackingEventIn>(size);
    var baseTime = new DateTime(2026, 9, 10, 0, 0, 0, DateTimeKind.Utc).AddMinutes(batchNo * 5);
    for (var i = 0; i < size; i++)
    {
        var tn = trackings[rnd.Next(trackings.Length)];
        list.Add(new TrackingEventIn(tn, $"sim-{worker}-{batchNo}-{i}-{Guid.NewGuid():N}"[..40], statuses[rnd.Next(statuses.Length)],
            baseTime.AddSeconds(i), "Москва", "127018", "simulator"));
    }
    return list;
}

static async Task<IEnumerable<string>> LoadTrackingsAsync(IDbConnectionFactory factory, int count)
{
    await using var conn = await factory.OpenAsync();
    return await conn.QueryAsync<string>("SELECT TOP (@count) TrackingNumber FROM ship.Shipment WHERE CarrierId = (SELECT CarrierId FROM ref.Carrier WHERE Code = 'FASTEX') AND DeliveredAt IS NULL ORDER BY ShipmentId DESC", new { count });
}

sealed record SimOptions(string Mode, int Workers, int Seconds, int BatchSize, string Api, string Connection, bool Cleanup)
{
    public static SimOptions Parse(string[] args)
    {
        string Get(string name, string def) { var i = Array.IndexOf(args, "--" + name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : def; }
        return new SimOptions(Get("mode", "tvp"), int.Parse(Get("workers", "4")), int.Parse(Get("seconds", "20")), int.Parse(Get("batch", "20")),
            Get("api", "http://localhost:5080"),
            Get("connection", Environment.GetEnvironmentVariable("WAYBILL_CONNECTION") ?? "Server=localhost;Database=Waybill;Integrated Security=true;Encrypt=Mandatory;TrustServerCertificate=true"),
            Array.IndexOf(args, "--keep") < 0);
    }
}
