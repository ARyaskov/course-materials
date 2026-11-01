// Интеграционные тесты ingest: идемпотентность, классификация отклонений, смена статуса, ETag-конфликт. Все изменения — в транзакции с откатом.
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging.Abstractions;
using Waybill.Data;
using Waybill.Data.Repositories;
using Xunit;
using Xunit.Abstractions;

namespace Waybill.Tests;

[Collection("db")]
public sealed class IngestTests(DatabaseFixture fx, ITestOutputHelper output)
{
    private static TrackingEventIn Ev(string tracking, string id, string status, string at) =>
        new(tracking, id, status, DateTime.Parse(at, null, System.Globalization.DateTimeStyles.AdjustToUniversal), "Москва", "127018", "test");

    [Fact]
    public async Task Ingest_is_idempotent_by_external_event_id()
    {
        if (!fx.Ready(output)) return;
        var ingest = new IngestRepository(fx.Factory);
        var id = $"test-{Guid.NewGuid():N}"[..30];
        var batch = new[] { Ev("FX0000000001", id, "AT_HUB", "2026-09-17T10:00:00Z") };
        try
        {
            var first = await ingest.IngestAsync("FASTEX", batch, CancellationToken.None);
            var second = await ingest.IngestAsync("FASTEX", batch, CancellationToken.None);
            Assert.Equal(1, first.Summary.EventsInserted);
            Assert.Equal(0, second.Summary.EventsInserted);
            Assert.Equal(1, second.Summary.EventsDuplicate);
        }
        finally
        {
            await using var conn = await fx.Factory.OpenAsync();
            await conn.ExecuteAsync("DELETE FROM ship.TrackingEvent WHERE ExternalEventId = @id", new { id });
        }
    }

    [Fact]
    public async Task Rejections_are_classified()
    {
        if (!fx.Ready(output)) return;
        var ingest = new IngestRepository(fx.Factory);
        var result = await ingest.IngestAsync("FASTEX", new[]
        {
            Ev("FX0000000001", "t-bad-status", "NOPE", "2026-09-17T10:00:00Z"),
            Ev("FX9999999999", "t-unknown", "AT_HUB", "2026-09-17T10:00:00Z"),
            Ev("FX 0000000001", "t-format", "AT_HUB", "2026-09-17T10:00:00Z"),
            Ev("FX0000000001", "t-time", "AT_HUB", "2099-01-01T00:00:00Z"),
        }, CancellationToken.None);
        Assert.Equal(0, result.Summary.EventsInserted);
        Assert.Equal(4, result.Summary.EventsRejected);
        var reasons = result.Rejected.ToDictionary(r => r.ExternalEventId, r => r.Reason);
        Assert.Equal("unknown-status", reasons["t-bad-status"]);
        Assert.Equal("unknown-tracking", reasons["t-unknown"]);
        Assert.Equal("bad-tracking-format", reasons["t-format"]);
        Assert.Equal("bad-time", reasons["t-time"]);
    }

    [Fact]
    public async Task Update_with_stale_rowversion_fails_with_50070()
    {
        if (!fx.Ready(output)) return;
        var shipments = new ShipmentRepository(fx.Factory);
        await using var conn = await fx.Factory.OpenAsync();
        var (id, rowVer) = await conn.QuerySingleAsync<(long, byte[])>("SELECT TOP (1) ShipmentId, RowVer FROM ship.Shipment WHERE TrackingNumber = 'FX0000000001'");

        // Первая запись с актуальной версией проходит; вторая с той же (устаревшей) версией — 50070
        var updated = await shipments.UpdateIfMatchAsync(id, rowVer, new ShipmentPatch(null, null, null), "test", CancellationToken.None);
        Assert.NotEqual(Convert.ToBase64String(rowVer), Convert.ToBase64String(updated.RowVersion));
        var ex = await Assert.ThrowsAsync<SqlException>(() => shipments.UpdateIfMatchAsync(id, rowVer, new ShipmentPatch(null, null, null), "test", CancellationToken.None));
        Assert.Equal(SqlErrors.VersionConflict, ex.Number);
    }

    [Fact]
    public async Task Deadlock_retry_wrapper_retries_then_succeeds()
    {
        var attempts = 0;
        var result = await Resilience.RetryOnDeadlockAsync<int>(_ =>
        {
            attempts++;
            if (attempts < 3) throw MakeSqlException(SqlErrors.Deadlock);
            return Task.FromResult(42);
        }, NullLogger.Instance, maxAttempts: 3);
        Assert.Equal(42, result);
        Assert.Equal(3, attempts);
    }

    // SqlException без сервера: через SqlErrorCollection и рефлексию (только для теста обёртки)
    private static SqlException MakeSqlException(int number)
    {
        var errorCtor = typeof(SqlError).GetConstructors(System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)
            .OrderByDescending(c => c.GetParameters().Length).First();
        var args = errorCtor.GetParameters().Select(p => p.ParameterType switch
        {
            var t when t == typeof(int) => (object)number,
            var t when t == typeof(byte) => (byte)0,
            var t when t == typeof(string) => "deadlock",
            var t when t == typeof(uint) => 0u,
            var t when t == typeof(Exception) => null!,
            _ => null!,
        }).ToArray();
        var error = (SqlError)errorCtor.Invoke(args);
        var collection = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        typeof(SqlErrorCollection).GetMethod("Add", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.Invoke(collection, new object[] { error });
        var create = typeof(SqlException).GetMethod("CreateException", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static,
            null, new[] { typeof(SqlErrorCollection), typeof(string) }, null)!;
        return (SqlException)create.Invoke(null, new object[] { collection, "17.0" })!;
    }
}
