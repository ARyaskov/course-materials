/*
  010_indexes_core.sql — индексы под запросы API Waybill (урок 4.3). Идемпотентен.
  1. Таймлайн отправления: ship.TrackingEvent (ShipmentId, OccurredAt)
  2. Поиск по трек-номеру без перевозчика: ship.Shipment (TrackingNumberNormalized)
  3. Список отправлений магазина: ship.Shipment (MerchantId, CreatedAt DESC, ShipmentId DESC)
  4. Адреса магазина по ключу дедупликации: ship.Address (MerchantId, NormalizedKey)
  + индексы под внешние ключи, у которых нет запросного индекса
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.TrackingEvent') AND name = N'IX_TrackingEvent_Shipment_OccurredAt')
    CREATE NONCLUSTERED INDEX IX_TrackingEvent_Shipment_OccurredAt
        ON ship.TrackingEvent (ShipmentId, OccurredAt)
        INCLUDE (StatusId, LocationText, LocationPostalCode, Description)
        ON FG_Events;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_TrackingNumberNormalized')
    CREATE NONCLUSTERED INDEX IX_Shipment_TrackingNumberNormalized
        ON ship.Shipment (TrackingNumberNormalized)
        INCLUDE (CarrierId, MerchantId, StatusId, PromisedAt, DeliveredAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Merchant_CreatedAt')
    CREATE NONCLUSTERED INDEX IX_Shipment_Merchant_CreatedAt
        ON ship.Shipment (MerchantId, CreatedAt DESC, ShipmentId DESC)
        INCLUDE (CarrierId, TrackingNumber, StatusId, PromisedAt, DeliveredAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'IX_Address_Merchant_NormalizedKey')
    CREATE NONCLUSTERED INDEX IX_Address_Merchant_NormalizedKey
        ON ship.Address (MerchantId, NormalizedKey);
GO

-- Индексы под FK
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_OriginAddress')
    CREATE NONCLUSTERED INDEX IX_Shipment_OriginAddress ON ship.Shipment (OriginAddressId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_DestinationAddress')
    CREATE NONCLUSTERED INDEX IX_Shipment_DestinationAddress ON ship.Shipment (DestinationAddressId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'IX_Address_Region')
    CREATE NONCLUSTERED INDEX IX_Address_Region ON ship.Address (RegionId) WHERE RegionId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'IX_Incident_Merchant_CreatedAt')
    CREATE NONCLUSTERED INDEX IX_Incident_Merchant_CreatedAt ON ops.Incident (MerchantId, CreatedAt DESC) INCLUDE (Severity, IsResolved, Title);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'IX_Incident_Shipment')
    CREATE NONCLUSTERED INDEX IX_Incident_Shipment ON ops.Incident (ShipmentId) WHERE ShipmentId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'IX_Incident_Carrier')
    CREATE NONCLUSTERED INDEX IX_Incident_Carrier ON ops.Incident (CarrierId) WHERE CarrierId IS NOT NULL;
GO

-- Горячая последняя страница у возрастающих ключей
ALTER INDEX PK_Shipment ON ship.Shipment SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);
ALTER INDEX PK_TrackingEvent ON ship.TrackingEvent SET (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);
GO
