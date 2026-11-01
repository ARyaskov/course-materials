/* 11-history/020_change_tracking.sql
   Change Tracking: включение на базе и на ship.Shipment / crm.Merchant, курсоры потребителей ops.SyncCursor,
   ops.usp_GetShipmentChanges — выборка изменений для синхронизации кэша/поискового индекса. Идемпотентен.
*/
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID(N'Waybill'))
    ALTER DATABASE Waybill SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 3 DAYS, AUTO_CLEANUP = ON);
GO
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(N'ship.Shipment'))
    ALTER TABLE ship.Shipment ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(N'crm.Merchant'))
    ALTER TABLE crm.Merchant ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);
GO

-- Курсор синхронизации на потребителя: до какой версии он забрал изменения
IF OBJECT_ID(N'ops.SyncCursor', N'U') IS NULL
    CREATE TABLE ops.SyncCursor
    (
        Consumer     varchar(64)  NOT NULL CONSTRAINT PK_SyncCursor PRIMARY KEY,
        TableName    sysname      NOT NULL,
        LastVersion  bigint       NOT NULL,
        UpdatedAt    datetime2(3) NOT NULL CONSTRAINT DF_SyncCursor_UpdatedAt DEFAULT SYSUTCDATETIME()
    );
GO

-- Изменения отправлений с последней синхронизации потребителя; возвращает строки и новую версию для подтверждения
CREATE OR ALTER PROCEDURE ops.usp_GetShipmentChanges
    @Consumer   varchar(64),
    @NewVersion bigint OUTPUT,
    @FullResync bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;      -- версия и данные из одной точки во времени
    BEGIN TRANSACTION;

    DECLARE @last bigint = (SELECT LastVersion FROM ops.SyncCursor WHERE Consumer = @Consumer AND TableName = N'ship.Shipment');
    DECLARE @minValid bigint = CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID(N'ship.Shipment'));
    SET @NewVersion = CHANGE_TRACKING_CURRENT_VERSION();
    SET @FullResync = IIF(@last IS NULL OR @last < @minValid, 1, 0);   -- курсора нет или он старше retention: полная пересинхронизация

    IF @FullResync = 1
        SELECT s.ShipmentId, 'I' AS Operation, s.PublicId, s.TrackingNumber, s.StatusId, s.MerchantId, s.CarrierId, s.PromisedAt, s.DeliveredAt, s.UpdatedAt
        FROM ship.Shipment AS s;
    ELSE
        SELECT ct.ShipmentId, ct.SYS_CHANGE_OPERATION AS Operation,
               s.PublicId, s.TrackingNumber, s.StatusId, s.MerchantId, s.CarrierId, s.PromisedAt, s.DeliveredAt, s.UpdatedAt,
               CHANGE_TRACKING_IS_COLUMN_IN_MASK(COLUMNPROPERTY(OBJECT_ID(N'ship.Shipment'), N'StatusId', 'ColumnId'), ct.SYS_CHANGE_COLUMNS) AS StatusChanged,
               ct.SYS_CHANGE_VERSION
        FROM CHANGETABLE(CHANGES ship.Shipment, @last) AS ct
        LEFT JOIN ship.Shipment AS s ON s.ShipmentId = ct.ShipmentId   -- для 'D' строки уже нет
        ORDER BY ct.SYS_CHANGE_VERSION;

    COMMIT;
END;
GO

-- Подтверждение: потребитель обработал изменения до версии
CREATE OR ALTER PROCEDURE ops.usp_AckShipmentChanges
    @Consumer varchar(64),
    @Version  bigint
AS
BEGIN
    SET NOCOUNT ON;
    MERGE ops.SyncCursor AS t
    USING (SELECT @Consumer AS Consumer, N'ship.Shipment' AS TableName) AS s ON t.Consumer = s.Consumer AND t.TableName = s.TableName
    WHEN MATCHED THEN UPDATE SET LastVersion = @Version, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (Consumer, TableName, LastVersion) VALUES (@Consumer, N'ship.Shipment', @Version);
END;
GO

-- diagnostic: safe to re-run
SELECT DB_NAME(database_id) AS db, is_auto_cleanup_on, retention_period, retention_period_units_desc FROM sys.change_tracking_databases;
SELECT OBJECT_NAME(object_id) AS table_name, is_track_columns_updated_on, min_valid_version, begin_version, cleanup_version FROM sys.change_tracking_tables;
SELECT CHANGE_TRACKING_CURRENT_VERSION() AS current_version, CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID(N'ship.Shipment')) AS min_valid;

-- Цикл потребителя: первый вызов — полная синхронизация, затем только изменения
DECLARE @v bigint, @full bit;
EXEC ops.usp_GetShipmentChanges @Consumer = 'search-index', @NewVersion = @v OUTPUT, @FullResync = @full OUTPUT;
SELECT @v AS new_version, @full AS full_resync;
EXEC ops.usp_AckShipmentChanges @Consumer = 'search-index', @Version = @v;

-- CT фиксирует только зафиксированные транзакции: изменения делаем и возвращаем назад двумя COMMIT-ами
DECLARE @id bigint = (SELECT MIN(ShipmentId) FROM ship.Shipment WHERE ExternalOrderId LIKE N'SEED-%'), @status tinyint;
SET @status = (SELECT StatusId FROM ship.Shipment WHERE ShipmentId = @id);
BEGIN TRANSACTION;
UPDATE ship.Shipment SET WeightGrams = WeightGrams WHERE ShipmentId IN (1, 2);   -- изменение без смены значения тоже фиксируется CT
UPDATE ship.Shipment SET StatusId = IIF(@status = 4, 3, 4) WHERE ShipmentId = @id;
COMMIT;
EXEC ops.usp_GetShipmentChanges @Consumer = 'search-index', @NewVersion = @v OUTPUT, @FullResync = @full OUTPUT;   -- 3 строки, StatusChanged = 1 у третьей
-- (без Ack: следующий вызов вернёт их снова — at-least-once)
UPDATE ship.Shipment SET StatusId = @status WHERE ShipmentId = @id;   -- вернуть как было (ещё одна версия CT и temporal)

DELETE FROM ops.SyncCursor WHERE Consumer = 'search-index';
GO
