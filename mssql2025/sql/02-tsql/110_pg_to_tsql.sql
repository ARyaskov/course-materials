-- diagnostic: safe to re-run
/*
  110_pg_to_tsql.sql — T-SQL-эквиваленты типичных запросов PostgreSQL (урок 2.10). Изменения откатываются.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. LIMIT/OFFSET, ILIKE, ::date
SELECT ShipmentId, TrackingNumber, CAST(CreatedAt AS date) AS CreatedDate
FROM demo.Shipment
WHERE City LIKE N'ber%'
ORDER BY CreatedAt DESC, ShipmentId DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 2. generate_series + date_trunc
SELECT CAST(DATEADD(DAY, g.value, '2026-09-01') AS date) AS Day, COUNT(s.ShipmentId) AS Shipments
FROM GENERATE_SERIES(0, 29) AS g
LEFT JOIN demo.Shipment AS s
       ON s.CreatedAt >= DATEADD(DAY, g.value, '2026-09-01')
      AND s.CreatedAt <  DATEADD(DAY, g.value + 1, '2026-09-01')
GROUP BY g.value
ORDER BY Day;

-- 3. DISTINCT ON
WITH ranked AS
(
    SELECT ShipmentId, Status, OccurredAt,
           ROW_NUMBER() OVER (PARTITION BY ShipmentId ORDER BY OccurredAt DESC, EventId DESC) AS rn
    FROM demo.TrackingEvent
)
SELECT TOP (10) ShipmentId, Status, OccurredAt FROM ranked WHERE rn = 1 ORDER BY ShipmentId;
GO

-- 4. RETURNING → OUTPUT; 5. ON CONFLICT → UPDATE+INSERT (в транзакции с откатом)
BEGIN TRANSACTION;
INSERT INTO demo.Shipment (MerchantId, CarrierId, TrackingNumber, Status, City, WeightGrams, DeclaredValue, CreatedAt, PromisedAt)
OUTPUT inserted.ShipmentId, inserted.CreatedAt
VALUES (1, 1, 'DM9000000001', 'CREATED', N'Москва', 100, 1, SYSUTCDATETIME(), DATEADD(HOUR, 48, SYSUTCDATETIME()));

UPDATE demo.Shipment SET Status = 'LOST'
OUTPUT deleted.Status AS OldStatus, inserted.Status AS NewStatus
WHERE ShipmentId = 5;

UPDATE demo.Carrier WITH (UPDLOCK, HOLDLOCK) SET SlaHours = 72 WHERE CarrierId = 4;
IF @@ROWCOUNT = 0
    INSERT INTO demo.Carrier (CarrierId, Code, SlaHours) VALUES (4, 'REGIONEXPRESS', 72);
SELECT * FROM demo.Carrier;
ROLLBACK;
GO

-- 6. LATERAL → CROSS APPLY
SELECT c.Code, e.TrackingNumber, e.WeightGrams
FROM demo.Carrier AS c
CROSS APPLY (SELECT TOP (3) s.TrackingNumber, s.WeightGrams FROM demo.Shipment AS s WHERE s.CarrierId = c.CarrierId ORDER BY s.WeightGrams DESC) AS e;

-- 7. array_agg / string_agg
SELECT ShipmentId,
       JSON_ARRAYAGG(Status ORDER BY OccurredAt) AS StatusesJson,
       STRING_AGG(Status, ' > ') WITHIN GROUP (ORDER BY OccurredAt) AS StatusPath
FROM demo.TrackingEvent WHERE ShipmentId <= 5 GROUP BY ShipmentId;

-- 8. FILTER / bool_or
SELECT CarrierId, SUM(IIF(DeliveredAt > PromisedAt, 1, 0)) AS Late, MAX(IIF(Status = 'LOST', 1, 0)) AS AnyLost
FROM demo.Shipment GROUP BY CarrierId;

-- 9. interval
SELECT TOP (5) TrackingNumber, DATEDIFF(MINUTE, CreatedAt, DeliveredAt) / 60.0 AS TransitHours, DATEADD(HOUR, 48, CreatedAt) AS Deadline
FROM demo.Shipment WHERE CreatedAt > DATEADD(DAY, -60, '2026-09-15');
GO

-- 10. Транзакционный DDL и последовательность
BEGIN TRANSACTION;
CREATE TABLE demo.TmpReport (Id int IDENTITY PRIMARY KEY, Note nvarchar(max));
ALTER TABLE demo.Shipment ADD Note nvarchar(400) NULL;
ROLLBACK;
SELECT OBJECT_ID(N'demo.TmpReport', N'U') AS tmp_report_exists, COL_LENGTH(N'demo.Shipment', N'Note') AS note_column;   -- оба NULL

IF OBJECT_ID(N'demo.EventSeq', N'SO') IS NULL
    CREATE SEQUENCE demo.EventSeq AS bigint START WITH 1 INCREMENT BY 1 CACHE 100;
SELECT NEXT VALUE FOR demo.EventSeq AS next_value;
GO

-- 11. Регулярные выражения (2025)
SELECT TOP (5) TrackingNumber, REGEXP_REPLACE(TrackingNumber, '\D', '') AS digits_only
FROM demo.Shipment WHERE REGEXP_LIKE(TrackingNumber, '^DM\d{10}$');
GO
