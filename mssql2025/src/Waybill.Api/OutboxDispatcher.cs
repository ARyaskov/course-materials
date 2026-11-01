// Диспетчер outbox (глава 13): BackgroundService, N воркеров, партиционированный dequeue, доставка по топикам, at-least-once.
using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Waybill.Data;
using Waybill.Data.Repositories;

namespace Waybill.Api;

public sealed class OutboxOptions
{
    public bool Enabled { get; set; } = true;
    public int Workers { get; set; } = 2;              // должно делить 16 (партиции AggregateId % 16)
    public int BatchSize { get; set; } = 50;
    public int LeaseSeconds { get; set; } = 60;
    public int IdleDelayMs { get; set; } = 1000;
    public int MaxIdleDelayMs { get; set; } = 5000;
    /// <summary>Topic → URL без подписи (глава 13, совместимость); с главы 17 цель — crm.MerchantWebhook по merchantId конверта.</summary>
    public Dictionary<string, string> Webhooks { get; set; } = new();
}

public sealed class OutboxDispatcher(OutboxRepository outbox, IOptions<OutboxOptions> options, IHttpClientFactory httpFactory, ILogger<OutboxDispatcher> logger) : BackgroundService
{
    private static readonly Meter Meter = new("Waybill.Api.Outbox");
    private static readonly Counter<long> Delivered = Meter.CreateCounter<long>("waybill.outbox.delivered");
    private static readonly Counter<long> Failed = Meter.CreateCounter<long>("waybill.outbox.failed");
    private static readonly Histogram<double> DeliveryMs = Meter.CreateHistogram<double>("waybill.outbox.delivery_ms");

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var o = options.Value;
        if (!o.Enabled) { logger.LogInformation("Outbox dispatcher disabled"); return; }
        if (16 % o.Workers != 0) throw new InvalidOperationException("Outbox:Workers must divide 16");

        var workerPrefix = $"{Environment.MachineName}:{Environment.ProcessId}";
        var tasks = Enumerable.Range(0, o.Workers).Select(p => RunWorkerAsync($"{workerPrefix}:{p}", (byte)o.Workers, (byte)p, stoppingToken)).ToArray();
        await Task.WhenAll(tasks);
    }

    private async Task RunWorkerAsync(string workerId, byte partitionCount, byte partition, CancellationToken ct)
    {
        var o = options.Value;
        var delay = o.IdleDelayMs;
        logger.LogInformation("Outbox worker {Worker} started (partition {Partition}/{Count})", workerId, partition, partitionCount);

        while (!ct.IsCancellationRequested)
        {
            IReadOnlyList<OutboxMessage> batch;
            try
            {
                batch = await outbox.DequeueAsync(workerId, o.BatchSize, o.LeaseSeconds, partitionCount, partition, ct);
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                logger.LogWarning(ex, "Outbox worker {Worker}: dequeue failed, backing off {Delay} ms", workerId, delay);   // база недоступна: ждём, не падаем
                await Task.Delay(delay, ct);
                delay = Math.Min(delay * 2, o.MaxIdleDelayMs);
                continue;
            }

            if (batch.Count == 0)
            {
                await Task.Delay(delay, ct);
                delay = Math.Min(delay * 2, o.MaxIdleDelayMs);   // backoff на пустой очереди
                continue;
            }
            delay = o.IdleDelayMs;

            var done = new List<long>(batch.Count);
            foreach (var msg in batch)                                    // по порядку внутри пачки: события одного агрегата — у этого воркера
            {
                var t0 = System.Diagnostics.Stopwatch.GetTimestamp();
                try
                {
                    await DeliverAsync(msg, CancellationToken.None);       // доставку не обрываем на остановке: аренда истечёт — повторим
                    done.Add(msg.OutboxId);
                    Delivered.Add(1, new KeyValuePair<string, object?>("topic", msg.Topic));
                }
                catch (Exception ex)
                {
                    Failed.Add(1, new KeyValuePair<string, object?>("topic", msg.Topic));
                    logger.LogWarning(ex, "Outbox {Id} topic {Topic} attempt {Attempt} failed", msg.OutboxId, msg.Topic, msg.Attempts);
                    await outbox.FailAsync(workerId, msg.OutboxId, ex.Message, CancellationToken.None);
                }
                finally
                {
                    DeliveryMs.Record(System.Diagnostics.Stopwatch.GetElapsedTime(t0).TotalMilliseconds);
                }
            }
            await outbox.CompleteAsync(workerId, done, CancellationToken.None);
        }
    }

    // Доставка (глава 17): цель — crm.MerchantWebhook по merchantId из конверта; фильтр notifyOn; подпись HMAC-SHA256; at-least-once.
    // Кэш целей на 60 с — чтобы не ходить в базу на каждое сообщение; отключённый вебхук — сообщение считается доставленным (лог).
    private readonly ConcurrentDictionary<int, (WebhookTarget? Target, DateTime Until)> _targets = new();

    private async Task DeliverAsync(OutboxMessage msg, CancellationToken ct)
    {
        using var doc = JsonDocument.Parse(msg.Payload);
        var root = doc.RootElement;
        var messageId = root.TryGetProperty("id", out var idProp) ? idProp.GetString() : msg.OutboxId.ToString();
        var data = root.TryGetProperty("data", out var d) ? d : root;
        var merchantId = data.TryGetProperty("merchantId", out var m) && m.TryGetInt32(out var mid) ? mid : (int?)null;

        // Совместимость с конфигурацией главы 13: URL по топику без подписи
        if (merchantId is null && options.Value.Webhooks.TryGetValue(msg.Topic, out var legacyUrl) && !string.IsNullOrWhiteSpace(legacyUrl))
        {
            await PostAsync(legacyUrl, msg.Payload, messageId, secret: null, ct);
            return;
        }
        if (merchantId is null)
        {
            logger.LogInformation("outbox {Id} {Topic}: no merchantId in payload — delivered to log", msg.OutboxId, msg.Topic);
            return;
        }

        var target = await ResolveTargetAsync(merchantId.Value, msg.OutboxId, ct);
        if (target is null || !target.IsEnabled)
        {
            logger.LogInformation("outbox {Id} {Topic} merchant {Merchant}: webhook not configured or disabled", msg.OutboxId, msg.Topic, merchantId);
            return;
        }
        if (!WantsStatus(target.NotifyOn, data))
        {
            logger.LogDebug("outbox {Id} merchant {Merchant}: status filtered by notifyOn", msg.OutboxId, merchantId);
            return;
        }

        try
        {
            await PostAsync(target.Url, msg.Payload, messageId, target.Secret, ct);
            await outbox.RecordWebhookResultAsync(merchantId.Value, true, null, Guid.TryParse(messageId, out var g) ? g : null, CancellationToken.None);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            await outbox.RecordWebhookResultAsync(merchantId.Value, false, ex.Message, null, CancellationToken.None);
            _targets.TryRemove(merchantId.Value, out _);      // цель могла быть выключена после 20 ошибок — перечитать
            throw;
        }
    }

    private async Task<WebhookTarget?> ResolveTargetAsync(int merchantId, long outboxId, CancellationToken ct)
    {
        if (_targets.TryGetValue(merchantId, out var cached) && cached.Until > DateTime.UtcNow) return cached.Target;
        var target = await outbox.ResolveTargetAsync(outboxId, ct);
        _targets[merchantId] = (target, DateTime.UtcNow.AddSeconds(60));
        return target;
    }

    // notifyOn: [] — все статусы; иначе newStatus события должен входить в список
    private static bool WantsStatus(string notifyOn, JsonElement data)
    {
        using var list = JsonDocument.Parse(string.IsNullOrWhiteSpace(notifyOn) ? "[]" : notifyOn);
        if (list.RootElement.ValueKind != JsonValueKind.Array || list.RootElement.GetArrayLength() == 0) return true;
        var status = data.TryGetProperty("newStatus", out var s) ? s.GetString() : null;
        if (status is null) return true;
        foreach (var item in list.RootElement.EnumerateArray())
            if (string.Equals(item.GetString(), status, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    // Подпись: X-Waybill-Timestamp (unix seconds) + X-Waybill-Signature: sha256=HMAC(secret, "{timestamp}.{body}")
    private async Task PostAsync(string url, string body, string? messageId, string? secret, CancellationToken ct)
    {
        var client = httpFactory.CreateClient("outbox");
        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = new StringContent(body, Encoding.UTF8, "application/cloudevents+json") };
        request.Headers.Add("X-Message-Id", messageId);
        if (secret is not null)
        {
            var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
            var mac = HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes($"{ts}.{body}"));
            request.Headers.Add("X-Waybill-Timestamp", ts);
            request.Headers.Add("X-Waybill-Signature", "sha256=" + Convert.ToHexStringLower(mac));
        }
        using var response = await client.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"webhook {url} → {(int)response.StatusCode}");
    }
}
