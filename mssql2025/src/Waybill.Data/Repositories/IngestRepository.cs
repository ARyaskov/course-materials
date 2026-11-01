// Приём событий: webhook как есть (usp_ReceiveWebhook) и пакет через TVP (usp_IngestTrackingEvents); SqlBulkCopy для файлов.
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.Server;

namespace Waybill.Data.Repositories;

public sealed class IngestRepository(IDbConnectionFactory db)
{
    /// <summary>Webhook перевозчика: хэш-дедупликация, валидация, разбор и ingest — всё на сервере.</summary>
    public async Task<IngestResult> ReceiveWebhookAsync(string carrierCode, string body, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync($"webhook:{carrierCode}", ct);
        await using var cmd = new SqlCommand("ops.usp_ReceiveWebhook", conn) { CommandType = CommandType.StoredProcedure, CommandTimeout = db.CommandTimeout };
        cmd.Parameters.Add(new SqlParameter("@CarrierCode", SqlDbType.VarChar, 16) { Value = carrierCode });
        cmd.Parameters.Add(new SqlParameter("@Body", SqlDbType.NVarChar, -1) { Value = body });   // nvarchar(max): сервер сам приводит к json и хэширует
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        return await ReadIngestResultAsync(reader, ct);
    }

    /// <summary>Пакет уже нормализованных событий через табличный параметр: одна команда, один план, любое число строк.</summary>
    public async Task<IngestResult> IngestAsync(string carrierCode, IReadOnlyCollection<TrackingEventIn> events, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync($"ingest:{carrierCode}", ct);
        await using var cmd = new SqlCommand("ops.usp_IngestTrackingEvents", conn) { CommandType = CommandType.StoredProcedure, CommandTimeout = db.CommandTimeout };
        cmd.Parameters.Add(new SqlParameter("@CarrierCode", SqlDbType.VarChar, 16) { Value = carrierCode });
        cmd.Parameters.Add(new SqlParameter("@Events", SqlDbType.Structured)
        {
            TypeName = "ops.tt_TrackingEventIn",
            Value = events.Count == 0 ? null : ToRecords(events),   // пустой TVP передаётся как NULL (= пустая таблица)
        });
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        return await ReadIngestResultAsync(reader, ct);
    }

    // Метаданные SqlDataRecord обязаны совпадать с ops.tt_TrackingEventIn по порядку, типам и длинам
    private static IEnumerable<SqlDataRecord> ToRecords(IEnumerable<TrackingEventIn> events)
    {
        var meta = new[]
        {
            new SqlMetaData("TrackingNumber", SqlDbType.VarChar, 64),
            new SqlMetaData("ExternalEventId", SqlDbType.VarChar, 64),
            new SqlMetaData("ExternalStatus", SqlDbType.VarChar, 32),
            new SqlMetaData("OccurredAt", SqlDbType.DateTime2, 0, 3),
            new SqlMetaData("LocationText", SqlDbType.NVarChar, 100),
            new SqlMetaData("LocationPostalCode", SqlDbType.VarChar, 16),
            new SqlMetaData("Description", SqlDbType.NVarChar, 400),
            new SqlMetaData("RawFragment", SqlDbType.NVarChar, SqlMetaData.Max),
        };
        foreach (var e in events)
        {
            var r = new SqlDataRecord(meta);
            r.SetString(0, e.TrackingNumber);
            r.SetString(1, e.ExternalEventId);
            r.SetString(2, e.ExternalStatus);
            r.SetDateTime(3, DateTime.SpecifyKind(e.OccurredAtUtc, DateTimeKind.Unspecified));
            SetNullable(r, 4, e.LocationText);
            SetNullable(r, 5, e.LocationPostalCode);
            SetNullable(r, 6, e.Description);
            SetNullable(r, 7, e.RawFragment);
            yield return r;                                       // стриминг: строки уходят по мере перечисления, без буфера
        }

        static void SetNullable(SqlDataRecord r, int i, string? v) { if (v is null) r.SetDBNull(i); else r.SetString(i, v); }
    }

    private static async Task<IngestResult> ReadIngestResultAsync(SqlDataReader reader, CancellationToken ct)
    {
        IngestSummary summary = new(0, 0, 0, 0, 0);
        if (await reader.ReadAsync(ct))
        {
            summary = new IngestSummary(
                reader.GetInt32(reader.GetOrdinal("EventsTotal")),
                reader.GetInt32(reader.GetOrdinal("EventsInserted")),
                reader.GetInt32(reader.GetOrdinal("EventsDuplicate")),
                reader.GetInt32(reader.GetOrdinal("EventsRejected")),
                reader.GetInt32(reader.GetOrdinal("StatusChanges")),
                HasColumn(reader, "Note") ? reader.GetString(reader.GetOrdinal("Note")) : null);
        }
        var rejected = new List<RejectedEvent>();
        if (await reader.NextResultAsync(ct))
        {
            while (await reader.ReadAsync(ct))
                rejected.Add(new RejectedEvent(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetDateTime(3), reader.GetString(4)));
        }
        return new IngestResult(summary, rejected);

        static bool HasColumn(SqlDataReader r, string name)
        {
            for (var i = 0; i < r.FieldCount; i++) if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    /// <summary>Файл/поток → ops.EventImportRaw через SqlBulkCopy (минимальное логирование при TableLock в SIMPLE/BULK_LOGGED).</summary>
    public async Task<long> BulkCopyRawAsync(IDataReader source, int batchSize, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        await conn.ExecuteAsync("TRUNCATE TABLE ops.EventImportRaw;");
        using var bulk = new SqlBulkCopy(conn, SqlBulkCopyOptions.TableLock | SqlBulkCopyOptions.UseInternalTransaction, null)
        {
            DestinationTableName = "ops.EventImportRaw",
            BatchSize = batchSize,
            BulkCopyTimeout = 0,
            EnableStreaming = true,
        };
        foreach (var col in new[] { "TrackingNumber", "ExternalEventId", "ExternalStatus", "OccurredAtText", "LocationText", "PostalCode", "Description" })
            bulk.ColumnMappings.Add(col, col);
        long copied = 0;
        bulk.NotifyAfter = batchSize;
        bulk.SqlRowsCopied += (_, e) => copied = e.RowsCopied;
        await bulk.WriteToServerAsync(source, ct);
        return copied == 0 ? bulk.RowsCopied : copied;
    }
}
