// Waybill.Api — minimal API поверх процедур Waybill (глава 12). Запуск: dotnet run --project src/Waybill.Api
// Строка подключения: appsettings.json → Waybill:ConnectionString, переопределяется переменной Waybill__ConnectionString.
using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Data.SqlClient;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Waybill.Api;
using Waybill.Data;
using Waybill.Data.Repositories;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<WaybillDbOptions>(builder.Configuration.GetSection(WaybillDbOptions.SectionName));
builder.Services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
builder.Services.AddSingleton<ShipmentRepository>();
builder.Services.AddSingleton<IngestRepository>();
builder.Services.AddSingleton<OutboxRepository>();
builder.Services.AddSingleton<IncidentRepository>();
builder.Services.AddSingleton<InvoiceRepository>();
builder.Services.Configure<AiOptions>(builder.Configuration.GetSection("Ai"));      // глава 14: эмбеддинги в приложении (Ai:Enabled)
builder.Services.AddHttpClient("ollama");
builder.Services.AddSingleton<EmbeddingService>();
builder.Services.AddProblemDetails();

// Диспетчер outbox (глава 13): N воркеров внутри API; отключается конфигурацией Outbox:Enabled=false
builder.Services.Configure<OutboxOptions>(builder.Configuration.GetSection("Outbox"));
builder.Services.AddHttpClient("outbox", c => c.Timeout = TimeSpan.FromSeconds(10));
builder.Services.AddHostedService<OutboxDispatcher>();

// Трейсы: HTTP-запрос → команды SqlClient (текст процедуры, длительность, ошибки) → консоль/OTLP
builder.Services.AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("Waybill.Api"))
    .WithTracing(t =>
    {
        t.AddAspNetCoreInstrumentation()
         .AddSqlClientInstrumentation(o => o.RecordException = true);
        if (builder.Configuration.GetValue<bool>("Telemetry:Console")) t.AddConsoleExporter();
    });

JsonParameters.Register();

var app = builder.Build();
app.UseExceptionHandler();
app.UseMiddleware<SqlExceptionMiddleware>();

// Пользователь до аутентификации главы 15: заголовок X-User → SESSION_CONTEXT('user') → ModifiedBy
static string UserOf(HttpRequest r) => r.Headers.TryGetValue("X-User", out var v) && !string.IsNullOrWhiteSpace(v) ? v.ToString() : "api:anonymous";
// Арендатор до аутентификации: заголовок X-Merchant-Id → SESSION_CONTEXT('MerchantId') → RLS (глава 15); после — из claims токена
static int? MerchantOf(HttpRequest r) => r.Headers.TryGetValue("X-Merchant-Id", out var v) && int.TryParse(v, out var id) ? id : null;

// --- Webhooks ---------------------------------------------------------------------------------------
app.MapPost("/webhooks/{carrier}", async (string carrier, HttpRequest request, IngestRepository ingest, ILogger<Program> log, CancellationToken ct) =>
{
    using var reader = new StreamReader(request.Body);
    var body = await reader.ReadToEndAsync(ct);                       // тело как есть: разбор и валидация — на сервере
    if (string.IsNullOrWhiteSpace(body)) return Results.Problem("Empty body", statusCode: 400);

    var result = await Resilience.RetryOnDeadlockAsync(token => ingest.ReceiveWebhookAsync(carrier.ToUpperInvariant(), body, token), log, ct: ct);
    var status = result.Summary.Note == "duplicate-webhook" ? 200 : 202;
    return Results.Json(new { result.Summary, result.Rejected }, statusCode: status);
});

// Пакет нормализованных событий (внутренние загрузчики, симулятор): TVP → usp_IngestTrackingEvents
app.MapPost("/carriers/{carrier}/events", async (string carrier, TrackingEventIn[] events, IngestRepository ingest, ILogger<Program> log, CancellationToken ct) =>
{
    if (events.Length == 0) return Results.Problem("No events", statusCode: 400);
    var result = await Resilience.RetryOnDeadlockAsync(token => ingest.IngestAsync(carrier.ToUpperInvariant(), events, token), log, ct: ct);
    return Results.Json(new { result.Summary, result.Rejected }, statusCode: 202);
});

// --- Shipments --------------------------------------------------------------------------------------
app.MapGet("/shipments/{tracking}/timeline", async Task<Results<ContentHttpResult, NotFound, StatusCodeHttpResult>> (
    string tracking, HttpRequest request, HttpResponse response, ShipmentRepository shipments, CancellationToken ct) =>
{
    int? merchantId = MerchantOf(request) ?? (request.Query.TryGetValue("merchantId", out var m) && int.TryParse(m, out var id) ? id : null);
    var doc = await shipments.GetTimelineAsync(tracking, merchantId, ct);
    if (doc is null) return TypedResults.NotFound();

    response.Headers.ETag = doc.ETag;
    if (request.Headers.IfNoneMatch.Contains(doc.ETag)) return TypedResults.StatusCode(304);   // условное чтение
    return TypedResults.Content(doc.Json, "application/json");
});

app.MapPatch("/shipments/{publicId:guid}", async (Guid publicId, ShipmentPatchDto dto, HttpRequest request, HttpResponse response,
    ShipmentRepository shipments, ILogger<Program> log, CancellationToken ct) =>
{
    var ifMatch = request.Headers.IfMatch.FirstOrDefault();
    if (ifMatch is null) return Results.Problem("If-Match is required", statusCode: 428);   // Precondition Required

    var current = await shipments.GetVersionByPublicIdAsync(publicId, ct);
    if (current is null) return Results.NotFound();

    byte[] expected;
    try { expected = Convert.FromBase64String(ifMatch.Trim('"')); }
    catch (FormatException) { return Results.Problem("If-Match is not a valid ETag", statusCode: 400); }

    var patch = new ShipmentPatch(dto.WeightGrams, dto.PromisedAt?.UtcDateTime, dto.Attributes is null ? null : JsonDocument.Parse(dto.Attributes.Value.GetRawText()));
    var updated = await Resilience.RetryOnDeadlockAsync(token => shipments.UpdateIfMatchAsync(current.ShipmentId, expected, patch, UserOf(request), token), log, ct: ct);
    response.Headers.ETag = updated.ETag;
    return Results.Ok(new { id = publicId, etag = updated.ETag });
});

app.MapGet("/shipments/{publicId:guid}/versions", async (Guid publicId, ShipmentRepository shipments, CancellationToken ct) =>
{
    var current = await shipments.GetVersionByPublicIdAsync(publicId, ct);
    if (current is null) return Results.NotFound();
    return Results.Ok(await shipments.GetVersionsAsync(current.ShipmentId, ct));
});

app.MapGet("/merchants/{merchantId:int}/shipments", async (int merchantId, DateTime? before, long? beforeId, int? pageSize, ShipmentRepository shipments, CancellationToken ct) =>
    Results.Ok(await shipments.ListAsync(merchantId, before, beforeId, Math.Clamp(pageSize ?? 50, 1, 200), ct)));

// Сортировка по имени столбца — ship.usp_ListShipmentsSorted: белый список + QUOTENAME на сервере (глава 15)
app.MapGet("/merchants/{merchantId:int}/shipments/sorted", async (int merchantId, string? sort, string? dir, byte? status, string? q, int? pageSize, ShipmentRepository shipments, CancellationToken ct) =>
    Results.Ok(await shipments.ListSortedAsync(merchantId, sort ?? "CreatedAt", dir ?? "DESC", status, q, Math.Clamp(pageSize ?? 50, 1, 200), ct)));

// --- Incidents (глава 14) --------------------------------------------------------------------------
app.MapGet("/incidents/{id:long}/similar", async (long id, int? top, bool? sameCarrier, bool? approximate, HttpRequest request, IncidentRepository incidents, CancellationToken ct) =>
    Results.Ok(await incidents.FindSimilarAsync(id, Math.Clamp(top ?? 5, 1, 50), sameCarrier ?? false, approximate ?? false, MerchantOf(request), ct)));

app.MapGet("/merchants/{merchantId:int}/incidents/search", async (int merchantId, string q, int? top, IncidentRepository incidents, EmbeddingService embeddings, CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(q)) return Results.Problem("q is required", statusCode: 400);
    var vector = await embeddings.EmbedAsync(q, ct);                                  // null → сервер посчитает сам (модель или toy)
    return Results.Ok(await incidents.SearchHybridAsync(merchantId, q.Trim(), vector, Math.Clamp(top ?? 10, 1, 50), ct));
});

app.MapPost("/incidents", async (NewIncident dto, HttpRequest request, IncidentRepository incidents, EmbeddingService embeddings, CancellationToken ct) =>
{
    var vector = await embeddings.EmbedAsync($"{dto.Title}. {dto.Description}", ct);
    var id = await incidents.CreateAsync(dto, vector, vector is null ? null : embeddings.Model, UserOf(request), ct);
    return Results.Created($"/incidents/{id}", new { incidentId = id, embedded = vector is not null });
});

// --- Invoices (глава 17) ---------------------------------------------------------------------------
app.MapPost("/merchants/{merchantId:int}/invoices/{month}", async (int merchantId, string month, HttpRequest request, InvoiceRepository invoices, CancellationToken ct) =>
{
    if (!DateOnly.TryParseExact(month + "-01", "yyyy-MM-dd", out var m)) return Results.Problem("month must be yyyy-MM", statusCode: 400);
    var header = await invoices.GenerateAsync(merchantId, m, UserOf(request), ct);
    return Results.Ok(header);
});

app.MapGet("/merchants/{merchantId:int}/invoices/{month}", async Task<IResult> (int merchantId, string month, InvoiceRepository invoices, CancellationToken ct) =>
{
    if (!DateOnly.TryParseExact(month + "-01", "yyyy-MM-dd", out var m)) return Results.Problem("month must be yyyy-MM", statusCode: 400);
    var report = await invoices.ReportAsync(merchantId, m, ct);
    return report.Header is null ? Results.NotFound() : Results.Ok(report);
});

app.MapPost("/merchants/{merchantId:int}/invoices/{invoiceId:long}/issue", async (int merchantId, long invoiceId, HttpRequest request, InvoiceRepository invoices, CancellationToken ct) =>
{
    await invoices.IssueAsync(merchantId, invoiceId, UserOf(request), ct);
    return Results.NoContent();
});

// --- Health -----------------------------------------------------------------------------------------
app.MapGet("/health", async (IDbConnectionFactory db, CancellationToken ct) =>
{
    try
    {
        await using var conn = await db.OpenAsync(ct);
        await using var cmd = new SqlCommand(
            "SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(32)) AS version, DB_NAME() AS db, " +
            "(SELECT actual_state_desc FROM sys.database_query_store_options) AS query_store, " +
            "(SELECT COUNT(*) FROM ops.Outbox WHERE ProcessedAt IS NULL AND Attempts < 10) AS outbox_pending", conn) { CommandTimeout = 5 };
        await using var r = await cmd.ExecuteReaderAsync(ct);
        await r.ReadAsync(ct);
        return Results.Ok(new { status = "ok", version = r.GetString(0), database = r.GetString(1), queryStore = r.GetString(2), outboxPending = r.GetInt32(3) });
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "unhealthy", error = ex.Message }, statusCode: 503);
    }
});

app.Run();

public sealed record ShipmentPatchDto(int? WeightGrams, DateTimeOffset? PromisedAt, JsonElement? Attributes);

public partial class Program { }   // для WebApplicationFactory в тестах
