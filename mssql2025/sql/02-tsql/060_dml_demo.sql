-- diagnostic: safe to re-run
/*
  060_dml_demo.sql — upsert двумя способами с OUTPUT (урок 2.5). Все изменения откатываются.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

-- Источник: два существующих трек-номера, три новых
DECLARE @src TABLE (TrackingNumber varchar(64) PRIMARY KEY, Status varchar(32), City nvarchar(100));
INSERT INTO @src VALUES
    ('DM0000000001', 'DELIVERED', N'Москва'),
    ('DM0000000002', 'RETURNED',  N'Санкт-Петербург'),
    ('DM7000000001', 'CREATED',   N'Екатеринбург'),
    ('DM7000000002', 'CREATED',   N'Новосибирск'),
    ('DM7000000003', 'CREATED',   N'Казань');

-- Способ 1: MERGE WITH (HOLDLOCK) — одно действие, результат через $action
DECLARE @merge_result TABLE (action nvarchar(10), ShipmentId bigint, TrackingNumber varchar(64));

MERGE demo.Shipment WITH (HOLDLOCK) AS target
USING @src AS src ON target.TrackingNumber = src.TrackingNumber
WHEN MATCHED AND target.Status IS DISTINCT FROM src.Status THEN
    UPDATE SET Status = src.Status
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MerchantId, CarrierId, TrackingNumber, Status, City, WeightGrams, DeclaredValue, CreatedAt, PromisedAt)
    VALUES (1, 1, src.TrackingNumber, src.Status, src.City, 100, 0, SYSUTCDATETIME(), DATEADD(HOUR, 48, SYSUTCDATETIME()))
OUTPUT $action, inserted.ShipmentId, inserted.TrackingNumber INTO @merge_result;

SELECT 'merge' AS method, * FROM @merge_result ORDER BY action, TrackingNumber;

ROLLBACK;   -- вернуть исходное состояние перед вторым способом
GO

BEGIN TRANSACTION;

DECLARE @src TABLE (TrackingNumber varchar(64) PRIMARY KEY, Status varchar(32), City nvarchar(100));
INSERT INTO @src VALUES
    ('DM0000000001', 'DELIVERED', N'Москва'),
    ('DM0000000002', 'RETURNED',  N'Санкт-Петербург'),
    ('DM7000000001', 'CREATED',   N'Екатеринбург'),
    ('DM7000000002', 'CREATED',   N'Новосибирск'),
    ('DM7000000003', 'CREATED',   N'Казань');

-- Способ 2: UPDATE + INSERT ... WHERE NOT EXISTS под UPDLOCK/HOLDLOCK; результат собирается из двух OUTPUT
DECLARE @result TABLE (action nvarchar(10), ShipmentId bigint, TrackingNumber varchar(64));

UPDATE t WITH (UPDLOCK, HOLDLOCK)
SET Status = src.Status
OUTPUT 'UPDATE', inserted.ShipmentId, inserted.TrackingNumber INTO @result
FROM demo.Shipment AS t
JOIN @src AS src ON src.TrackingNumber = t.TrackingNumber
WHERE t.Status IS DISTINCT FROM src.Status;

INSERT INTO demo.Shipment (MerchantId, CarrierId, TrackingNumber, Status, City, WeightGrams, DeclaredValue, CreatedAt, PromisedAt)
OUTPUT 'INSERT', inserted.ShipmentId, inserted.TrackingNumber INTO @result
SELECT 1, 1, src.TrackingNumber, src.Status, src.City, 100, 0, SYSUTCDATETIME(), DATEADD(HOUR, 48, SYSUTCDATETIME())
FROM @src AS src
WHERE NOT EXISTS (SELECT 1 FROM demo.Shipment AS t WITH (UPDLOCK, HOLDLOCK) WHERE t.TrackingNumber = src.TrackingNumber);

SELECT 'update+insert' AS method, * FROM @result ORDER BY action, TrackingNumber;

ROLLBACK;
GO
