// Очередь outbox: аренда пачки, подтверждение, ошибка (глава 8); используется диспетчером (глава 13).
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.Server;

namespace Waybill.Data.Repositories;

public sealed class OutboxRepository(IDbConnectionFactory db)
{
    public Task<IReadOnlyList<OutboxMessage>> DequeueAsync(string workerId, int batchSize, int leaseSeconds, CancellationToken ct) =>
        DequeueAsync(workerId, batchSize, leaseSeconds, null, null, ct);

    /// <summary>Партиционированный dequeue (глава 13): воркер partition из partitionCount берёт только свои агрегаты.</summary>
    public async Task<IReadOnlyList<OutboxMessage>> DequeueAsync(string workerId, int batchSize, int leaseSeconds, byte? partitionCount, byte? partition, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        var rows = await conn.QueryAsync<OutboxMessage>(new CommandDefinition("ops.usp_DequeueOutbox",
            new { BatchSize = batchSize, LeaseSeconds = leaseSeconds, WorkerId = new DbString { Value = workerId, Length = 64 }, MaxAttempts = (byte)10,
                  PartitionCount = partitionCount, Partition = partition },
            commandType: CommandType.StoredProcedure, commandTimeout: db.CommandTimeout, cancellationToken: ct));
        return rows.AsList();
    }

    public async Task CompleteAsync(string workerId, IReadOnlyCollection<long> ids, CancellationToken ct)
    {
        if (ids.Count == 0) return;
        await using var conn = await db.OpenAsync(ct);
        await using var cmd = new SqlCommand("ops.usp_CompleteOutbox", conn) { CommandType = CommandType.StoredProcedure };
        cmd.Parameters.Add(new SqlParameter("@Ids", SqlDbType.Structured) { TypeName = "ops.tt_IdList", Value = IdRecords(ids) });
        cmd.Parameters.Add(new SqlParameter("@WorkerId", SqlDbType.NVarChar, 64) { Value = workerId });
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task FailAsync(string workerId, long outboxId, string error, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        await conn.ExecuteAsync(new CommandDefinition("ops.usp_FailOutbox",
            new { OutboxId = outboxId, WorkerId = new DbString { Value = workerId, Length = 64 }, Error = new DbString { Value = error.Length > 1000 ? error[..1000] : error, Length = 1000 } },
            commandType: CommandType.StoredProcedure, cancellationToken: ct));
    }

    /// <summary>Цель доставки для сообщения (глава 17): URL и секрет магазина из crm.MerchantWebhook; null — доставка не настроена.</summary>
    public async Task<WebhookTarget?> ResolveTargetAsync(long outboxId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        return await conn.QuerySingleOrDefaultAsync<WebhookTarget>(new CommandDefinition("ops.usp_ResolveOutboxTarget",
            new { OutboxId = outboxId }, commandType: CommandType.StoredProcedure, cancellationToken: ct));
    }

    public async Task RecordWebhookResultAsync(int merchantId, bool success, string? error, Guid? messageId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        await conn.ExecuteAsync(new CommandDefinition("ops.usp_RecordWebhookResult",
            new { MerchantId = merchantId, Success = success, Error = error is null ? null : new DbString { Value = error.Length > 400 ? error[..400] : error, Length = 400 }, MessageId = messageId },
            commandType: CommandType.StoredProcedure, cancellationToken: ct));
    }

    private static IEnumerable<SqlDataRecord> IdRecords(IEnumerable<long> ids)
    {
        var meta = new[] { new SqlMetaData("Id", SqlDbType.BigInt) };
        foreach (var id in ids) { var r = new SqlDataRecord(meta); r.SetInt64(0, id); yield return r; }
    }
}
