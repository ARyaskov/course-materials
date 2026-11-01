/*
  020_functions.sql — функции (урок 7.4). Идемпотентен.
  ship.tvf_ShipmentTimeline  — inline TVF: события отправления с расшифровкой статуса
  ship.fn_IsTerminalStatus   — скалярная (инлайнится): терминальный ли статус
  ship.tvf_ShipmentSummary   — inline TVF: сводка по отправлению для API
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER FUNCTION ship.tvf_ShipmentTimeline (@ShipmentId bigint)
RETURNS TABLE
AS
RETURN
    SELECT e.EventId, e.OccurredAt, e.ReceivedAt, e.StatusId, st.Code AS StatusCode, st.Name AS StatusName,
           e.LocationText, e.LocationPostalCode, e.Description, e.ExternalEventId,
           ROW_NUMBER() OVER (ORDER BY e.OccurredAt, e.EventId) AS Seq
    FROM ship.TrackingEvent AS e
    JOIN ref.ShipmentStatus AS st ON st.StatusId = e.StatusId
    WHERE e.ShipmentId = @ShipmentId;
GO

CREATE OR ALTER FUNCTION ship.fn_IsTerminalStatus (@StatusId tinyint)
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    RETURN (SELECT IsTerminal FROM ref.ShipmentStatus WHERE StatusId = @StatusId);
END;
GO

CREATE OR ALTER FUNCTION ship.tvf_ShipmentSummary (@ShipmentId bigint)
RETURNS TABLE
AS
RETURN
    SELECT s.ShipmentId, s.PublicId, s.TrackingNumber, c.Code AS CarrierCode, m.Code AS MerchantCode,
           st.Code AS StatusCode, st.IsTerminal, s.CreatedAt, s.PromisedAt, s.DeliveredAt, s.LastEventAt,
           IIF(s.DeliveredAt IS NULL AND s.PromisedAt < SYSUTCDATETIME(), 1, 0) AS IsOverdue,
           (SELECT COUNT(*) FROM ship.TrackingEvent AS e WHERE e.ShipmentId = s.ShipmentId) AS EventCount
    FROM ship.Shipment AS s
    JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId
    JOIN crm.Merchant AS m ON m.MerchantId = s.MerchantId
    JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
    WHERE s.ShipmentId = @ShipmentId;
GO

CREATE OR ALTER FUNCTION ship.tvf_OverdueShipments (@MerchantId int, @AsOf datetime2(3))
RETURNS TABLE
AS
RETURN
    SELECT s.ShipmentId, s.TrackingNumber, s.CarrierId, s.PromisedAt,
           DATEDIFF(HOUR, s.PromisedAt, @AsOf) AS OverdueHours,
           last.StatusCode AS LastStatus, last.OccurredAt AS LastEventAt
    FROM ship.Shipment AS s
    OUTER APPLY (SELECT TOP (1) t.StatusCode, t.OccurredAt FROM ship.tvf_ShipmentTimeline(s.ShipmentId) AS t ORDER BY t.Seq DESC) AS last
    WHERE (@MerchantId IS NULL OR s.MerchantId = @MerchantId)
      AND s.DeliveredAt IS NULL AND s.PromisedAt < @AsOf;
GO

SELECT name, is_inlineable FROM sys.sql_modules AS m JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE o.name IN (N'fn_IsTerminalStatus', N'fn_NormalizeTrackingNumber', N'fn_NormalizeStreet', N'fn_NormalizePhone');
GO
