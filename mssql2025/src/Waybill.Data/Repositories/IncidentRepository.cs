// Инциденты и векторный поиск (глава 14): похожие инциденты (точный / ANN), гибридный поиск, создание с эмбеддингом.
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace Waybill.Data.Repositories;

public sealed record SimilarIncident(long IncidentId, string Title, byte Severity, bool IsResolved, DateTime CreatedAt, string? Carrier, decimal Distance);
public sealed record IncidentSearchHit(long IncidentId, string Title, byte Severity, bool IsResolved, DateTime CreatedAt, decimal Score, int? TextRank, int? VectorRank);
public sealed record NewIncident(long? ShipmentId, int MerchantId, short? CarrierId, string Title, string Description, byte Severity);

public sealed class IncidentRepository(IDbConnectionFactory db)
{
    public async Task<IReadOnlyList<SimilarIncident>> FindSimilarAsync(long incidentId, int top, bool sameCarrier, bool approximate, int? merchantId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);   // с арендатором чужой исходный инцидент «не существует» (RLS)
        var proc = approximate ? "ops.usp_FindSimilarIncidentsAnn" : "ops.usp_FindSimilarIncidents";
        object args = approximate ? new { IncidentId = incidentId, Top = top } : new { IncidentId = incidentId, Top = top, SameCarrier = sameCarrier };
        var rows = await conn.QueryAsync<SimilarIncident>(new CommandDefinition(proc, args, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        return rows.AsList();
    }

    /// <summary>Гибридный поиск: текст + вектор (RRF). Эмбеддинг запроса — от приложения (float[]) или на сервере (null).</summary>
    public async Task<IReadOnlyList<IncidentSearchHit>> SearchHybridAsync(int merchantId, string query, float[]? queryEmbedding, int top, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);
        await using var cmd = new SqlCommand("ops.usp_SearchIncidentsHybrid", conn) { CommandType = CommandType.StoredProcedure, CommandTimeout = db.CommandTimeout };
        cmd.Parameters.Add(new SqlParameter("@MerchantId", SqlDbType.Int) { Value = merchantId });
        cmd.Parameters.Add(new SqlParameter("@Query", SqlDbType.NVarChar, 200) { Value = query });
        cmd.Parameters.Add(new SqlParameter("@QueryEmbedding", SqlDbType.NVarChar, -1) { Value = queryEmbedding is null ? DBNull.Value : VectorText(queryEmbedding) });   // vector принимает JSON-массив текстом
        cmd.Parameters.Add(new SqlParameter("@Top", SqlDbType.Int) { Value = top });
        var list = new List<IncidentSearchHit>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            list.Add(new IncidentSearchHit(r.GetInt64(0), r.GetString(1), r.GetByte(2), r.GetBoolean(3), r.GetDateTime(4), r.GetDecimal(5),
                await r.IsDBNullAsync(6, ct) ? null : r.GetInt32(6), await r.IsDBNullAsync(7, ct) ? null : r.GetInt32(7)));
        return list;
    }

    /// <summary>Создать инцидент; эмбеддинг — сразу от приложения (если есть) или отложенно на сервере (usp_EmbedPendingIncidents).</summary>
    public async Task<long> CreateAsync(NewIncident incident, float[]? embedding, string? embeddingModel, string user, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(user, ct);
        var id = await conn.ExecuteScalarAsync<long>(new CommandDefinition(
            """
            INSERT INTO ops.Incident (ShipmentId, MerchantId, CarrierId, Title, Description, Severity, Embedding, EmbeddingModel, EmbeddedAt)
            OUTPUT inserted.IncidentId
            VALUES (@ShipmentId, @MerchantId, @CarrierId, @Title, @Description, @Severity,
                    CAST(@Embedding AS vector(768)), @EmbeddingModel, IIF(@Embedding IS NULL, NULL, SYSUTCDATETIME()));
            """,
            new
            {
                incident.ShipmentId, incident.MerchantId, incident.CarrierId,
                Title = incident.Title, Description = incident.Description, incident.Severity,
                Embedding = embedding is null ? null : VectorText(embedding),
                EmbeddingModel = embeddingModel is null ? null : new DbString { Value = embeddingModel, IsAnsi = true, Length = 64 },
            }, cancellationToken: ct));
        await conn.ExecuteAsync(new CommandDefinition("ops.usp_ChunkIncident", new { IncidentId = id }, commandType: CommandType.StoredProcedure, cancellationToken: ct));
        return id;
    }

    public async Task<int> EmbedPendingAsync(int batchSize, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        return await conn.ExecuteScalarAsync<int>(new CommandDefinition("ops.usp_EmbedPendingIncidents", new { BatchSize = batchSize }, commandType: CommandType.StoredProcedure, cancellationToken: ct));
    }

    /// <summary>Вектор → текст JSON-массива, который сервер приводит к vector(n). Инвариантная культура: точка как разделитель.</summary>
    public static string VectorText(float[] v) => "[" + string.Join(",", v.Select(x => x.ToString("R", System.Globalization.CultureInfo.InvariantCulture))) + "]";
}
