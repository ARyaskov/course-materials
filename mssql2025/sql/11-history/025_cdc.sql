/* 11-history/025_cdc.sql
   Change Data Capture на ship.Shipment: включение (требует SQL Server Agent), выборка изменений по LSN,
   ops.usp_GetShipmentCdcChanges для ETL-потребителя с курсором по LSN. Без Agent — печатает предупреждение и выходит.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- CDC требует запущенного SQL Server Agent (capture/cleanup jobs); в контейнере: MSSQL_AGENT_ENABLED=true
IF NOT EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%' AND status_desc = N'Running')
BEGIN
    PRINT 'CDC: SQL Server Agent не запущен — включение пропущено (запустите Agent и повторите скрипт)';
    IF OBJECT_ID(N'tempdb..#cdc_skip') IS NULL CREATE TABLE #cdc_skip (x int);
    RETURN;
END;

IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME()) = 0
    EXEC sys.sp_cdc_enable_db;

IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID(N'ship.Shipment'))
    EXEC sys.sp_cdc_enable_table
         @source_schema = N'ship', @source_name = N'Shipment',
         @role_name = N'waybill_cdc_reader',                 -- роль с правом читать изменения (создаётся автоматически)
         @capture_instance = N'ship_Shipment',
         @supports_net_changes = 1,                         -- fn_cdc_get_net_changes_*: одна строка на ключ за интервал
         @captured_column_list = N'ShipmentId, MerchantId, CarrierId, TrackingNumber, StatusId, PromisedAt, DeliveredAt, LastEventAt, WeightGrams, UpdatedAt, ModifiedBy',
         @filegroup_name = N'FG_Events';                    -- таблица изменений на отдельной файловой группе
GO

-- Курсор ETL-потребителя по LSN
IF OBJECT_ID(N'ops.CdcCursor', N'U') IS NULL
    CREATE TABLE ops.CdcCursor
    (
        Consumer        varchar(64)  NOT NULL CONSTRAINT PK_CdcCursor PRIMARY KEY,
        CaptureInstance sysname      NOT NULL,
        LastLsn         binary(10)   NOT NULL,
        UpdatedAt       datetime2(3) NOT NULL CONSTRAINT DF_CdcCursor_UpdatedAt DEFAULT SYSUTCDATETIME()
    );
GO

-- Процедуры создаются только при включённом CDC (функции cdc.fn_cdc_get_all_changes_* существуют)
IF OBJECT_ID(N'tempdb..#cdc_skip') IS NULL AND (SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME()) = 1
BEGIN
  IF EXISTS (SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID(N'ship.Shipment'))
  BEGIN
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE ops.usp_GetShipmentCdcChanges
    @Consumer varchar(64),
    @ToLsn    binary(10) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @fromLsn binary(10) = (SELECT LastLsn FROM ops.CdcCursor WHERE Consumer = @Consumer AND CaptureInstance = N''ship_Shipment'');
    DECLARE @minLsn binary(10) = sys.fn_cdc_get_min_lsn(N''ship_Shipment'');
    SET @ToLsn = sys.fn_cdc_get_max_lsn();

    IF @fromLsn IS NULL OR @fromLsn < @minLsn
        SET @fromLsn = @minLsn;                                 -- старт или курсор за retention: с самого раннего доступного
    ELSE
        SET @fromLsn = sys.fn_cdc_increment_lsn(@fromLsn);      -- интервалы включительные: следующий за подтверждённым

    IF @fromLsn > @ToLsn RETURN;                                -- новых изменений нет

    SELECT __$start_lsn AS StartLsn, __$seqval AS SeqVal,
           CASE __$operation WHEN 1 THEN ''delete'' WHEN 2 THEN ''insert'' WHEN 3 THEN ''update-before'' WHEN 4 THEN ''update-after'' END AS Operation,
           sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS CommitTime,
           ShipmentId, MerchantId, CarrierId, TrackingNumber, StatusId, PromisedAt, DeliveredAt, LastEventAt, WeightGrams, UpdatedAt, ModifiedBy,
           sys.fn_cdc_is_bit_set(sys.fn_cdc_get_column_ordinal(N''ship_Shipment'', N''StatusId''), __$update_mask) AS StatusChanged
    FROM cdc.fn_cdc_get_all_changes_ship_Shipment(@fromLsn, @ToLsn, N''all update old'')
    ORDER BY __$start_lsn, __$seqval;
END;';
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE ops.usp_AckShipmentCdcChanges
    @Consumer varchar(64),
    @Lsn      binary(10)
AS
BEGIN
    SET NOCOUNT ON;
    MERGE ops.CdcCursor AS t
    USING (SELECT @Consumer AS Consumer, N''ship_Shipment'' AS CaptureInstance) AS s ON t.Consumer = s.Consumer AND t.CaptureInstance = s.CaptureInstance
    WHEN MATCHED THEN UPDATE SET LastLsn = @Lsn, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (Consumer, CaptureInstance, LastLsn) VALUES (@Consumer, N''ship_Shipment'', @Lsn);
END;';
  END;
END;
GO

-- diagnostic: safe to re-run
IF OBJECT_ID(N'tempdb..#cdc_skip') IS NOT NULL BEGIN DROP TABLE #cdc_skip; RETURN; END;
SELECT capture_instance, OBJECT_NAME(source_object_id) AS source_table, supports_net_changes, create_date FROM cdc.change_tables;
SELECT j.job_type, j.maxtrans, j.maxscans, j.continuous, j.pollinginterval, j.retention, j.threshold FROM msdb.dbo.cdc_jobs AS j WHERE j.database_id = DB_ID();
SELECT sys.fn_cdc_get_min_lsn(N'ship_Shipment') AS min_lsn, sys.fn_cdc_get_max_lsn() AS max_lsn;

-- Изменение → через несколько секунд (capture job) появляется в cdc.ship_Shipment_CT
DECLARE @id bigint = (SELECT MIN(ShipmentId) FROM ship.Shipment WHERE ExternalOrderId LIKE N'SEED-%'), @w int;
SET @w = (SELECT WeightGrams FROM ship.Shipment WHERE ShipmentId = @id);
UPDATE ship.Shipment SET WeightGrams = @w + 1 WHERE ShipmentId = @id;
UPDATE ship.Shipment SET WeightGrams = @w WHERE ShipmentId = @id;
WAITFOR DELAY '00:00:06';
DECLARE @to binary(10);
EXEC ops.usp_GetShipmentCdcChanges @Consumer = 'warehouse-etl', @ToLsn = @to OUTPUT;   -- update-before/update-after × 2
SELECT @to AS to_lsn;
DELETE FROM ops.CdcCursor WHERE Consumer = 'warehouse-etl';
GO
