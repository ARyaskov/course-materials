-- diagnostic: safe to re-run
/*
  030_select_demo.sql — TOP, OFFSET/FETCH против keyset, CROSS/OUTER APPLY, рекурсивный CTE (урок 2.2).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_demo_Shipment_Merchant_Created' AND object_id = OBJECT_ID(N'demo.Shipment'))
    CREATE INDEX IX_demo_Shipment_Merchant_Created ON demo.Shipment (MerchantId, CreatedAt DESC, ShipmentId DESC);
GO

-- 1. Вторая страница по 25: OFFSET/FETCH
SET STATISTICS IO ON;
SELECT ShipmentId, TrackingNumber, CreatedAt
FROM demo.Shipment
WHERE MerchantId = 2
ORDER BY CreatedAt DESC, ShipmentId DESC
OFFSET 25 ROWS FETCH NEXT 25 ROWS ONLY;

-- 1б. Та же страница через keyset: последний ключ первой страницы берём подзапросом
DECLARE @lastCreatedAt datetime2(3), @lastId bigint;
SELECT TOP (1) @lastCreatedAt = CreatedAt, @lastId = ShipmentId
FROM (SELECT TOP (25) CreatedAt, ShipmentId FROM demo.Shipment WHERE MerchantId = 2 ORDER BY CreatedAt DESC, ShipmentId DESC) AS p
ORDER BY CreatedAt, ShipmentId;

SELECT TOP (25) ShipmentId, TrackingNumber, CreatedAt
FROM demo.Shipment
WHERE MerchantId = 2
  AND (CreatedAt < @lastCreatedAt OR (CreatedAt = @lastCreatedAt AND ShipmentId < @lastId))
ORDER BY CreatedAt DESC, ShipmentId DESC;
SET STATISTICS IO OFF;
GO

-- 2. Три самых поздних доставленных отправления на перевозчика
SELECT c.Code, x.TrackingNumber, x.DeliveredAt
FROM demo.Carrier AS c
CROSS APPLY
(
    SELECT TOP (3) s.TrackingNumber, s.DeliveredAt
    FROM demo.Shipment AS s
    WHERE s.CarrierId = c.CarrierId AND s.DeliveredAt IS NOT NULL
    ORDER BY s.DeliveredAt DESC
) AS x
ORDER BY c.Code, x.DeliveredAt DESC;
GO

-- 3. Рассинхрон: последнее событие OUT_FOR_DELIVERY, а статус отправления DELIVERED
SELECT s.ShipmentId, s.Status, last_evt.Status AS last_event_status, last_evt.OccurredAt
FROM demo.Shipment AS s
OUTER APPLY
(
    SELECT TOP (1) t.Status, t.OccurredAt
    FROM demo.TrackingEvent AS t
    WHERE t.ShipmentId = s.ShipmentId
    ORDER BY t.OccurredAt DESC, t.EventId DESC
) AS last_evt
WHERE s.Status = 'DELIVERED' AND last_evt.Status = 'OUT_FOR_DELIVERY';
GO

-- 4. Цепочка статусов рекурсивным CTE
WITH chain AS
(
    SELECT 1 AS step, CAST('ACCEPTED' AS varchar(32)) AS status
    UNION ALL
    SELECT step + 1,
           CAST(CASE status WHEN 'ACCEPTED' THEN 'IN_TRANSIT' WHEN 'IN_TRANSIT' THEN 'AT_HUB'
                            WHEN 'AT_HUB' THEN 'OUT_FOR_DELIVERY' WHEN 'OUT_FOR_DELIVERY' THEN 'DELIVERED' END AS varchar(32))
    FROM chain
    WHERE status <> 'DELIVERED'
)
SELECT step, status FROM chain OPTION (MAXRECURSION 10);
GO
