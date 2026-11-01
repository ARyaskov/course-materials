/* 11-history/010_temporal.sql
   ship.Shipment → system-versioned temporal table с историей ship.ShipmentHistory (PAGE-сжатие, retention 24 месяца),
   столбец ModifiedBy (кто менял: SESSION_CONTEXT('user') или логин). Функции чтения истории. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- 1. Кто изменил строку: temporal хранит «когда», но не «кто» (столбец добавлен в 07-procs/010_types.sql; здесь — страховка)
IF COL_LENGTH(N'ship.Shipment', N'ModifiedBy') IS NULL
    ALTER TABLE ship.Shipment ADD ModifiedBy sysname NOT NULL
        CONSTRAINT DF_Shipment_ModifiedBy DEFAULT (ISNULL(CAST(SESSION_CONTEXT(N'user') AS sysname), ORIGINAL_LOGIN()));
GO

-- 2. Столбцы периода (HIDDEN: не попадают в SELECT * и INSERT без списка столбцов)
IF COL_LENGTH(N'ship.Shipment', N'ValidFrom') IS NULL
BEGIN
    ALTER TABLE ship.Shipment ADD
        ValidFrom datetime2(3) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL CONSTRAINT DF_Shipment_ValidFrom DEFAULT SYSUTCDATETIME(),
        ValidTo   datetime2(3) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL CONSTRAINT DF_Shipment_ValidTo   DEFAULT CONVERT(datetime2(3), '9999-12-31 23:59:59.999'),
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo);
END;
GO

-- 3. Включение версионирования: историю создаёт сервер (та же структура, rowversion → binary(8), вычисляемые → обычные столбцы)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(N'ship.Shipment') AND temporal_type = 2)
BEGIN
    ALTER TABLE ship.Shipment SET (SYSTEM_VERSIONING = ON
        (HISTORY_TABLE = ship.ShipmentHistory, DATA_CONSISTENCY_CHECK = ON, HISTORY_RETENTION_PERIOD = 24 MONTHS));
END;
GO

-- 4. История: columnstore здесь невозможен — в ship.Shipment есть rowversion (RowVer) и json (Attributes), а история копирует типы
--    (rowversion остаётся timestamp), и columnstore такие столбцы не принимает (ошибка 35343). Замена: сжатие PAGE на кластерном
--    индексе истории (он же обслуживает retention-очистку) + некластерный индекс для точечных AS OF по отправлению.
--    Columnstore-история — для таблиц без rowversion/json/xml (см. урок 11.3).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.ShipmentHistory') AND index_id = 1)
    CREATE CLUSTERED INDEX IX_ShipmentHistory_Period ON ship.ShipmentHistory (ValidTo, ValidFrom) WITH (DATA_COMPRESSION = PAGE);   -- если история осталась heap
IF NOT EXISTS (SELECT 1 FROM sys.partitions WHERE object_id = OBJECT_ID(N'ship.ShipmentHistory') AND index_id = 1 AND data_compression = 2)
BEGIN
    DECLARE @ix sysname = (SELECT name FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.ShipmentHistory') AND index_id = 1);
    DECLARE @sql nvarchar(400) = CONCAT(N'ALTER INDEX ', QUOTENAME(@ix), N' ON ship.ShipmentHistory REBUILD WITH (DATA_COMPRESSION = PAGE);');
    EXEC sys.sp_executesql @sql;
END;
-- retention задаётся здесь (а не при включении версионирования): требует кластерного индекса истории по периоду
IF (SELECT history_retention_period FROM sys.tables WHERE object_id = OBJECT_ID(N'ship.Shipment')) <> 24
    ALTER TABLE ship.Shipment SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = ship.ShipmentHistory, HISTORY_RETENTION_PERIOD = 24 MONTHS));
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.ShipmentHistory') AND name = N'IX_ShipmentHistory_Shipment_ValidTo')
    CREATE NONCLUSTERED INDEX IX_ShipmentHistory_Shipment_ValidTo ON ship.ShipmentHistory (ShipmentId, ValidTo, ValidFrom) WITH (DATA_COMPRESSION = PAGE);   -- точечные запросы AS OF по отправлению
GO

-- 5. Функции чтения истории
-- Каким было отправление в момент времени
CREATE OR ALTER FUNCTION ship.tvf_ShipmentAsOf (@ShipmentId bigint, @AsOf datetime2(3))
RETURNS TABLE
AS
RETURN
    SELECT s.ShipmentId, s.TrackingNumber, s.StatusId, st.Code AS StatusCode, s.WeightGrams, s.PromisedAt, s.DeliveredAt, s.LastEventAt,
           s.ModifiedBy, s.ValidFrom, s.ValidTo
    FROM ship.Shipment FOR SYSTEM_TIME AS OF @AsOf AS s
    JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
    WHERE s.ShipmentId = @ShipmentId;
GO

-- Все версии отправления с тем, что изменилось относительно предыдущей
CREATE OR ALTER FUNCTION ship.tvf_ShipmentVersions (@ShipmentId bigint)
RETURNS TABLE
AS
RETURN
    WITH v AS
    (
        SELECT s.ShipmentId, s.ValidFrom, s.ValidTo, s.StatusId, s.WeightGrams, s.PromisedAt, s.DeliveredAt, s.DestinationAddressId, s.Attributes, s.ModifiedBy,
               ROW_NUMBER() OVER (ORDER BY s.ValidFrom) AS VersionNo
        FROM ship.Shipment FOR SYSTEM_TIME ALL AS s
        WHERE s.ShipmentId = @ShipmentId
    )
    -- Типы результата — контракт для Dapper (ShipmentHistoryVersion): int + bit, а не bigint от ROW_NUMBER и int от IIF
    SELECT CAST(c.VersionNo AS int) AS VersionNo, c.ValidFrom, c.ValidTo, c.ModifiedBy,
           c.StatusId, CAST(IIF(p.StatusId IS DISTINCT FROM c.StatusId, 1, 0) AS bit) AS StatusChanged,
           c.WeightGrams, CAST(IIF(p.WeightGrams IS DISTINCT FROM c.WeightGrams, 1, 0) AS bit) AS WeightChanged,
           c.PromisedAt, CAST(IIF(p.PromisedAt IS DISTINCT FROM c.PromisedAt, 1, 0) AS bit) AS PromisedChanged,
           c.DestinationAddressId, CAST(IIF(p.DestinationAddressId IS DISTINCT FROM c.DestinationAddressId, 1, 0) AS bit) AS AddressChanged,
           CAST(IIF(CAST(p.Attributes AS nvarchar(max)) IS DISTINCT FROM CAST(c.Attributes AS nvarchar(max)), 1, 0) AS bit) AS AttributesChanged,
           CAST(IIF(c.ValidTo = '9999-12-31 23:59:59.999', 1, 0) AS bit) AS IsCurrent
    FROM v AS c
    LEFT JOIN v AS p ON p.VersionNo = c.VersionNo - 1;
GO

-- Аудит смен статуса за период: кто, когда, из какого в какой
CREATE OR ALTER FUNCTION ship.tvf_StatusChangeAudit (@From datetime2(3), @To datetime2(3))
RETURNS TABLE
AS
RETURN
    SELECT h.ShipmentId, h.ValidFrom AS ChangedAt, h.ModifiedBy,
           prev.Code AS FromStatus, cur.Code AS ToStatus
    FROM ship.Shipment FOR SYSTEM_TIME FROM @From TO @To AS h
    CROSS APPLY (SELECT TOP (1) p.StatusId FROM ship.Shipment FOR SYSTEM_TIME ALL AS p
                 WHERE p.ShipmentId = h.ShipmentId AND p.ValidTo = h.ValidFrom ORDER BY p.ValidFrom DESC) AS pv
    JOIN ref.ShipmentStatus AS prev ON prev.StatusId = pv.StatusId
    JOIN ref.ShipmentStatus AS cur  ON cur.StatusId  = h.StatusId
    WHERE h.StatusId <> pv.StatusId;
GO

-- diagnostic: safe to re-run (изменения откатываются)
SELECT t.name, t.temporal_type_desc, h.name AS history_table, t.history_retention_period, t.history_retention_period_unit_desc
FROM sys.tables AS t LEFT JOIN sys.tables AS h ON h.object_id = t.history_table_id
WHERE t.object_id = OBJECT_ID(N'ship.Shipment');

BEGIN TRANSACTION;
EXEC sys.sp_set_session_context @key = N'user', @value = N'operator:anna';
UPDATE ship.Shipment SET WeightGrams = WeightGrams + 10 WHERE ShipmentId = 1;
UPDATE ship.Shipment SET StatusId = 5 WHERE ShipmentId = 1;
SELECT * FROM ship.tvf_ShipmentVersions(1) ORDER BY VersionNo;
SELECT * FROM ship.tvf_ShipmentAsOf(1, DATEADD(MINUTE, -1, SYSUTCDATETIME()));
ROLLBACK;
EXEC sys.sp_set_session_context @key = N'user', @value = NULL;
GO
