/*
  090_temp_objects_demo.sql — #temp против табличной переменной, TVP и процедура demo.usp_IngestEvents (урок 2.8).
  Создаёт тип demo.tt_TrackingEventIn и процедуру demo.usp_IngestEvents (идемпотентно).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Три варианта одного расчёта: смотрите Estimated Rows на операторе чтения временного объекта
SET STATISTICS IO ON;

DROP TABLE IF EXISTS #delivered_ix;
CREATE TABLE #delivered_ix (ShipmentId bigint NOT NULL PRIMARY KEY, CarrierId smallint NOT NULL, TransitMinutes int NOT NULL, INDEX IX_carrier (CarrierId));
INSERT INTO #delivered_ix SELECT ShipmentId, CarrierId, DATEDIFF(MINUTE, CreatedAt, DeliveredAt) FROM demo.Shipment WHERE DeliveredAt IS NOT NULL;
SELECT c.Code, COUNT(*) AS n, AVG(d.TransitMinutes) / 60.0 AS avg_hours FROM #delivered_ix AS d JOIN demo.Carrier AS c ON c.CarrierId = d.CarrierId GROUP BY c.Code;

DECLARE @delivered TABLE (ShipmentId bigint NOT NULL PRIMARY KEY, CarrierId smallint NOT NULL, TransitMinutes int NOT NULL);
INSERT INTO @delivered SELECT ShipmentId, CarrierId, DATEDIFF(MINUTE, CreatedAt, DeliveredAt) FROM demo.Shipment WHERE DeliveredAt IS NOT NULL;
SELECT c.Code, COUNT(*) AS n, AVG(d.TransitMinutes) / 60.0 AS avg_hours FROM @delivered AS d JOIN demo.Carrier AS c ON c.CarrierId = d.CarrierId GROUP BY c.Code;

DROP TABLE IF EXISTS #delivered_heap;
SELECT ShipmentId, CarrierId, DATEDIFF(MINUTE, CreatedAt, DeliveredAt) AS TransitMinutes INTO #delivered_heap FROM demo.Shipment WHERE DeliveredAt IS NOT NULL;
SELECT c.Code, COUNT(*) AS n, AVG(d.TransitMinutes) / 60.0 AS avg_hours FROM #delivered_heap AS d JOIN demo.Carrier AS c ON c.CarrierId = d.CarrierId GROUP BY c.Code;

SET STATISTICS IO OFF;
DROP TABLE IF EXISTS #delivered_ix;
DROP TABLE IF EXISTS #delivered_heap;
GO

-- 2. Табличный тип и процедура ingest на полигоне
IF TYPE_ID(N'demo.tt_TrackingEventIn') IS NULL
CREATE TYPE demo.tt_TrackingEventIn AS TABLE
(
    TrackingNumber   varchar(64)   NOT NULL,
    ExternalEventId  varchar(64)   NOT NULL,
    Status           varchar(32)   NOT NULL,
    OccurredAt       datetime2(3)  NOT NULL,
    Location         nvarchar(100) NULL,
    INDEX IX_tt_TrackingEventIn_Tracking (TrackingNumber, OccurredAt),
    PRIMARY KEY (ExternalEventId)
);
GO

CREATE OR ALTER PROCEDURE demo.usp_IngestEvents
    @Events demo.tt_TrackingEventIn READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO demo.TrackingEvent (ShipmentId, Status, OccurredAt, Location)
    OUTPUT inserted.EventId, inserted.ShipmentId
    SELECT s.ShipmentId, e.Status, e.OccurredAt, e.Location
    FROM @Events AS e
    JOIN demo.Shipment AS s ON s.TrackingNumber = e.TrackingNumber
    WHERE NOT EXISTS (SELECT 1 FROM demo.TrackingEvent AS t
                      WHERE t.ShipmentId = s.ShipmentId AND t.Status = e.Status AND t.OccurredAt = e.OccurredAt);
END;
GO

-- Двойной вызов одним пакетом: второй должен вернуть 0 строк
BEGIN TRANSACTION;
DECLARE @batch demo.tt_TrackingEventIn;
INSERT INTO @batch (TrackingNumber, ExternalEventId, Status, OccurredAt, Location)
VALUES ('DM0000000001', 'ext-1', 'AT_HUB', '2026-09-16T08:00:00', N'Москва, сортировочный центр'),
       ('DM0000000002', 'ext-2', 'IN_TRANSIT', '2026-09-16T09:00:00', N'Санкт-Петербург');
EXEC demo.usp_IngestEvents @Events = @batch;   -- 2 строки
EXEC demo.usp_IngestEvents @Events = @batch;   -- 0 строк
ROLLBACK;
GO
