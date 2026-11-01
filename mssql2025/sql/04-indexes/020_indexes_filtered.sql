/*
  020_indexes_filtered.sql — фильтрованные индексы и индекс по вычисляемому столбцу (урок 4.4). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Активные отправления с приближающимся дедлайном
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Active_PromisedAt')
    CREATE NONCLUSTERED INDEX IX_Shipment_Active_PromisedAt
        ON ship.Shipment (PromisedAt)
        INCLUDE (MerchantId, CarrierId, StatusId, TrackingNumber)
        WHERE DeliveredAt IS NULL;
GO

-- Необработанный outbox: воркер читает только это
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Outbox') AND name = N'IX_Outbox_Pending')
    CREATE NONCLUSTERED INDEX IX_Outbox_Pending
        ON ops.Outbox (CreatedAt, OutboxId)
        INCLUDE (Topic, LockedUntil, Attempts)
        WHERE ProcessedAt IS NULL;
GO

-- Открытые инциденты по серьёзности
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ops.Incident') AND name = N'IX_Incident_Open')
    CREATE NONCLUSTERED INDEX IX_Incident_Open
        ON ops.Incident (Severity DESC, CreatedAt)
        INCLUDE (MerchantId, Title)
        WHERE IsResolved = 0;
GO

-- Тяжёлые активные отправления перевозчика (фильтр по вычисляемому PERSISTED-столбцу)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Heavy_Active')
    CREATE NONCLUSTERED INDEX IX_Shipment_Heavy_Active
        ON ship.Shipment (CarrierId, PromisedAt)
        WHERE WeightGrams >= 10000 AND DeliveredAt IS NULL;   -- фильтр не принимает вычисляемые столбцы (даже PERSISTED): условие класса 'L' переписано по исходному столбцу
GO

-- Дата события (вычисляемый столбец без PERSISTED) + статус — для дневных срезов
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.TrackingEvent') AND name = N'IX_TrackingEvent_OccurredDate_Status')
    CREATE NONCLUSTERED INDEX IX_TrackingEvent_OccurredDate_Status
        ON ship.TrackingEvent (OccurredDate, StatusId)
        ON FG_Events;
GO
