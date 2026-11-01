using System.Text.Json;

namespace Waybill.Data;

/// <summary>Строка ops.tt_TrackingEventIn — вход ingest.</summary>
public sealed record TrackingEventIn(
    string TrackingNumber,
    string ExternalEventId,
    string ExternalStatus,
    DateTime OccurredAtUtc,
    string? LocationText = null,
    string? LocationPostalCode = null,
    string? Description = null,
    string? RawFragment = null);

/// <summary>Сводка ingest (набор 1 usp_IngestTrackingEvents / usp_ReceiveWebhook).</summary>
public sealed record IngestSummary(int EventsTotal, int EventsInserted, int EventsDuplicate, int EventsRejected, int StatusChanges, string? Note = null);

/// <summary>Отклонённое событие (набор 2).</summary>
public sealed record RejectedEvent(string TrackingNumber, string ExternalEventId, string ExternalStatus, DateTime OccurredAt, string Reason);

public sealed record IngestResult(IngestSummary Summary, IReadOnlyList<RejectedEvent> Rejected);

/// <summary>Документ таймлайна: JSON как есть (собран на сервере) + версия строки для ETag.</summary>
public sealed record TimelineDocument(string Json, byte[] RowVersion)
{
    public string ETag => $"\"{Convert.ToBase64String(RowVersion)}\"";
}

public sealed record ShipmentVersion(long ShipmentId, byte[] RowVersion)
{
    public string ETag => $"\"{Convert.ToBase64String(RowVersion)}\"";
}

/// <summary>Патч карточки: null — не менять.</summary>
public sealed record ShipmentPatch(int? WeightGrams, DateTime? PromisedAtUtc, JsonDocument? Attributes);

public sealed record ShipmentSortedItem(long ShipmentId, Guid PublicId, string TrackingNumber, string ExternalOrderId, byte StatusId, DateTime CreatedAt, DateTime? PromisedAt, DateTime? DeliveredAt, int WeightGrams);

public sealed record ShipmentListItem(long ShipmentId, Guid PublicId, string TrackingNumber, string Carrier, string Status, DateTime CreatedAt, DateTime? PromisedAt, DateTime? DeliveredAt);

/// <summary>Версия отправления из temporal-истории (ship.tvf_ShipmentVersions).</summary>
public sealed record ShipmentHistoryVersion(int VersionNo, DateTime ValidFrom, DateTime ValidTo, string ModifiedBy, byte StatusId,
    bool StatusChanged, int WeightGrams, bool WeightChanged, DateTime? PromisedAt, bool PromisedChanged, bool AddressChanged, bool AttributesChanged, bool IsCurrent);

/// <summary>Запись outbox, взятая в аренду (usp_DequeueOutbox).</summary>
/// <summary>Цель webhook-доставки магазина (crm.MerchantWebhook, глава 17).</summary>
public sealed record WebhookTarget(int MerchantId, string Url, string Secret, string? SecretPrevious, string NotifyOn, bool IsEnabled);

/// <summary>Счёт магазина за месяц (bill.Invoice, глава 17).</summary>
public sealed record InvoiceHeader(long InvoiceId, int MerchantId, DateTime PeriodStart, DateTime PeriodEnd, string Currency, decimal Total, int Lines, byte Status, DateTime? IssuedAt);
public sealed record InvoiceReportLine(string Carrier, string Region, int Shipments, decimal Amount, int WithoutTariff);
public sealed record InvoiceReport(InvoiceHeader? Header, IReadOnlyList<InvoiceReportLine> Lines);

public sealed record OutboxMessage(long OutboxId, string Topic, string AggregateType, long AggregateId, string Payload, byte Attempts, DateTime LockedUntil);
