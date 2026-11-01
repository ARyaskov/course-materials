// Отправления: таймлайн (JSON собирает сервер), версия/ETag, условное обновление, temporal-версии, поиск.
using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace Waybill.Data.Repositories;

public sealed class ShipmentRepository(IDbConnectionFactory db)
{
    /// <summary>Документ таймлайна и RowVer для ETag. null — не найдено (или чужой магазин).</summary>
    public async Task<TimelineDocument?> GetTimelineAsync(string trackingNumber, int? merchantId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);   // при заданном арендаторе чужое отправление не найдётся (RLS)
        // Два запроса на одном соединении: документ + версия строки (RowVer не входит в JSON — он для заголовка)
        var doc = await conn.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
            "ship.usp_GetShipmentTimeline",
            new { TrackingNumber = new DbString { Value = trackingNumber, IsAnsi = true, Length = 64 }, MerchantId = merchantId },
            commandType: CommandType.StoredProcedure, commandTimeout: db.CommandTimeout, cancellationToken: ct));
        if (doc is null) return null;

        var rowVer = await conn.QuerySingleAsync<byte[]>(new CommandDefinition(
            "SELECT RowVer FROM ship.Shipment WHERE TrackingNumberNormalized = ship.fn_NormalizeTrackingNumber(@tracking)",
            new { tracking = new DbString { Value = trackingNumber, IsAnsi = true, Length = 64 } },
            cancellationToken: ct));
        return new TimelineDocument(doc, rowVer);
    }

    public async Task<ShipmentVersion?> GetVersionByPublicIdAsync(Guid publicId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        var row = await conn.QuerySingleOrDefaultAsync<(long ShipmentId, byte[] RowVer)>(new CommandDefinition(
            "SELECT ShipmentId, RowVer FROM ship.Shipment WHERE PublicId = @publicId", new { publicId }, cancellationToken: ct));
        return row.RowVer is null ? null : new ShipmentVersion(row.ShipmentId, row.RowVer);
    }

    /// <summary>PATCH с If-Match: 50070 → конфликт версий, 50001 → не найдено. Возвращает новую версию.</summary>
    public async Task<ShipmentVersion> UpdateIfMatchAsync(long shipmentId, byte[] expectedRowVer, ShipmentPatch patch, string user, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(user, ct);
        var p = new DynamicParameters();
        p.Add("@ShipmentId", shipmentId, DbType.Int64);
        p.Add("@ExpectedRowVer", expectedRowVer, DbType.Binary, size: 8);
        p.Add("@WeightGrams", patch.WeightGrams, DbType.Int32);
        p.Add("@PromisedAt", patch.PromisedAtUtc, DbType.DateTime2);
        p.Add("@Attributes", patch.Attributes?.RootElement.GetRawText(), DbType.String);   // json-параметр: строка → неявно json на сервере
        p.Add("@NewRowVer", dbType: DbType.Binary, size: 8, direction: ParameterDirection.Output);
        await conn.ExecuteAsync(new CommandDefinition("ship.usp_UpdateShipmentIfMatch", p, commandType: CommandType.StoredProcedure,
            commandTimeout: db.CommandTimeout, cancellationToken: ct));
        return new ShipmentVersion(shipmentId, p.Get<byte[]>("@NewRowVer"));
    }

    /// <summary>Temporal-лента версий (глава 11).</summary>
    public async Task<IReadOnlyList<ShipmentHistoryVersion>> GetVersionsAsync(long shipmentId, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(ct);
        var rows = await conn.QueryAsync<ShipmentHistoryVersion>(new CommandDefinition(
            """
            SELECT VersionNo, ValidFrom, ValidTo, ModifiedBy, StatusId, StatusChanged, WeightGrams, WeightChanged,
                   PromisedAt, PromisedChanged, AddressChanged, AttributesChanged, IsCurrent
            FROM ship.tvf_ShipmentVersions(@shipmentId) WHERE ValidFrom <> ValidTo ORDER BY VersionNo
            """, new { shipmentId }, cancellationToken: ct));
        return rows.AsList();
    }

    /// <summary>Список с сортировкой по имени столбца: белый список и QUOTENAME — на сервере (ship.usp_ListShipmentsSorted, глава 15).</summary>
    public async Task<IReadOnlyList<ShipmentSortedItem>> ListSortedAsync(int merchantId, string sortColumn, string sortDir, byte? status, string? search, int pageSize, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);
        var rows = await conn.QueryAsync<ShipmentSortedItem>(new CommandDefinition(
            "ship.usp_ListShipmentsSorted",
            new { MerchantId = merchantId, SortColumn = sortColumn, SortDir = sortDir, Status = status, Search = search, PageSize = pageSize },
            commandType: CommandType.StoredProcedure, commandTimeout: db.CommandTimeout, cancellationToken: ct));
        return rows.AsList();
    }

    /// <summary>Список отправлений магазина: keyset-пагинация по (CreatedAt DESC, ShipmentId DESC) — индекс IX_Shipment_Merchant_CreatedAt.</summary>
    public async Task<IReadOnlyList<ShipmentListItem>> ListAsync(int merchantId, DateTime? beforeCreatedAt, long? beforeId, int pageSize, CancellationToken ct)
    {
        await using var conn = await db.OpenAsync(null, merchantId, ct);   // RLS + предикат запроса: два независимых слоя
        var rows = await conn.QueryAsync<ShipmentListItem>(new CommandDefinition(
            """
            SELECT TOP (@pageSize) s.ShipmentId, s.PublicId, s.TrackingNumber, c.Code AS Carrier, st.Code AS Status, s.CreatedAt, s.PromisedAt, s.DeliveredAt
            FROM ship.Shipment AS s
            JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
            JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
            WHERE s.MerchantId = @merchantId
              AND (@beforeCreatedAt IS NULL OR s.CreatedAt < @beforeCreatedAt OR (s.CreatedAt = @beforeCreatedAt AND s.ShipmentId < @beforeId))
            ORDER BY s.CreatedAt DESC, s.ShipmentId DESC
            """, new { merchantId, beforeCreatedAt, beforeId, pageSize }, cancellationToken: ct));
        return rows.AsList();
    }
}
