/* 10-bulk/030_sliding_window.sql
   Скользящее окно секций ship.TrackingEvent: секции впереди (SPLIT пустой правой), архивирование старых
   (SWITCH → stage → архив columnstore → TRUNCATE секции stage → MERGE пустой левой границы).
   Объекты: ship.TrackingEventStage (та же структура, та же схема), ship.TrackingEventArchive (ordered CCI),
   ops.usp_MaintainEventPartitions. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Stage: структура и индексы 1:1 с ship.TrackingEvent на той же схеме — условие SWITCH
IF OBJECT_ID(N'ship.TrackingEventStage', N'U') IS NULL
BEGIN
    CREATE TABLE ship.TrackingEventStage
    (
        EventId             bigint        NOT NULL IDENTITY(1, 1),   -- свойства столбцов совпадают с ship.TrackingEvent
        ShipmentId          bigint        NOT NULL,
        CarrierId           smallint      NOT NULL,
        ExternalEventId     varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,
        StatusId            tinyint       NOT NULL,
        OccurredAt          datetime2(3)  NOT NULL,
        ReceivedAt          datetime2(3)  NOT NULL,
        LocationText        nvarchar(200) NULL,
        LocationPostalCode  varchar(16)   NULL,
        Description         nvarchar(400) NULL,
        OccurredDate        AS CAST(OccurredAt AS date),
        RawPayload          json          NULL,
        CONSTRAINT PK_TrackingEventStage PRIMARY KEY CLUSTERED (OccurredAt, EventId) ON ps_MonthlyEvents (OccurredAt),
        CONSTRAINT UQ_TrackingEventStage_Carrier_External UNIQUE NONCLUSTERED (CarrierId, ExternalEventId, OccurredAt) ON ps_MonthlyEvents (OccurredAt),
        CONSTRAINT FK_TrackingEventStage_Shipment FOREIGN KEY (ShipmentId) REFERENCES ship.Shipment (ShipmentId),
        CONSTRAINT FK_TrackingEventStage_Carrier  FOREIGN KEY (CarrierId)  REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT FK_TrackingEventStage_Status   FOREIGN KEY (StatusId)   REFERENCES ref.ShipmentStatus (StatusId),
        CONSTRAINT CK_TrackingEventStage_OccurredAt CHECK (OccurredAt >= '2020-01-01' AND OccurredAt < '2100-01-01')
    ) ON ps_MonthlyEvents (OccurredAt);
    CREATE NONCLUSTERED INDEX IX_TrackingEventStage_Shipment_OccurredAt ON ship.TrackingEventStage (ShipmentId, OccurredAt)
        INCLUDE (StatusId, LocationText, LocationPostalCode, Description) ON ps_MonthlyEvents (OccurredAt);
    CREATE NONCLUSTERED INDEX IX_TrackingEventStage_OccurredDate_Status ON ship.TrackingEventStage (OccurredDate, StatusId) ON ps_MonthlyEvents (OccurredAt);
    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TrackingEventStage ON ship.TrackingEventStage (ShipmentId, CarrierId, StatusId, OccurredAt, LocationPostalCode)
        ON ps_MonthlyEvents (OccurredAt);
END;
GO

-- Архив: ordered clustered columnstore (2022+), без секционирования — MERGE функции его не касается
IF OBJECT_ID(N'ship.TrackingEventArchive', N'U') IS NULL
BEGIN
    CREATE TABLE ship.TrackingEventArchive
    (
        EventId             bigint        NOT NULL,
        ShipmentId          bigint        NOT NULL,
        CarrierId           smallint      NOT NULL,
        ExternalEventId     varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,
        StatusId            tinyint       NOT NULL,
        OccurredAt          datetime2(3)  NOT NULL,
        ReceivedAt          datetime2(3)  NOT NULL,
        LocationText        nvarchar(200) NULL,
        LocationPostalCode  varchar(16)   NULL,
        Description         nvarchar(400) NULL,
        RawPayload          json          NULL,
        ArchivedAt          datetime2(3)  NOT NULL CONSTRAINT DF_TrackingEventArchive_ArchivedAt DEFAULT SYSUTCDATETIME()
    ) ON FG_Events;
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_TrackingEventArchive ON ship.TrackingEventArchive ORDER (OccurredAt) ON FG_Events;
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_MaintainEventPartitions
    @MonthsAhead  int = 2,       -- сколько будущих месяцев держать готовыми
    @RetainMonths int = 12,      -- сколько полных месяцев держать в горячей таблице
    @DryRun       bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @sql nvarchar(max), @b datetime2(3), @msg nvarchar(400);
    DECLARE @thisMonth date = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1);

    /* 1. SPLIT: границы до @thisMonth + @MonthsAhead + 1 (секция за последним месяцем должна быть пустой, иначе SPLIT двигает данные) */
    DECLARE @maxBound datetime2(3) = (SELECT MAX(CAST(value AS datetime2(3))) FROM sys.partition_range_values AS v
                                      JOIN sys.partition_functions AS f ON f.function_id = v.function_id WHERE f.name = N'pf_MonthlyEvents');
    DECLARE @needBound datetime2(3) = DATEADD(MONTH, @MonthsAhead + 1, @thisMonth);
    WHILE @maxBound < @needBound
    BEGIN
        SET @maxBound = DATEADD(MONTH, 1, @maxBound);
        SET @sql = CONCAT(N'ALTER PARTITION SCHEME ps_MonthlyEvents NEXT USED [FG_Events]; ',
                          N'ALTER PARTITION FUNCTION pf_MonthlyEvents() SPLIT RANGE (''', CONVERT(char(10), @maxBound, 120), N''');');
        PRINT CONCAT(IIF(@DryRun = 1, 'dry-run: ', 'exec: '), @sql);
        IF @DryRun = 0 EXEC sys.sp_executesql @sql;
    END;

    /* 2. Архивирование: секции, чья верхняя граница <= @thisMonth - @RetainMonths */
    DECLARE @cutoff datetime2(3) = DATEADD(MONTH, -@RetainMonths, @thisMonth);
    DECLARE @pn int, @rows bigint;
    DECLARE parts CURSOR LOCAL STATIC FOR
        SELECT p.partition_number, p.rows, CAST(nb.value AS datetime2(3)) AS upper_bound
        FROM sys.partitions AS p
        JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
        JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
        JOIN sys.partition_range_values AS nb ON nb.function_id = ps.function_id AND nb.boundary_id = p.partition_number   -- верхняя граница (RANGE RIGHT)
        WHERE p.object_id = OBJECT_ID(N'ship.TrackingEvent') AND i.index_id = 1
          AND CAST(nb.value AS datetime2(3)) <= @cutoff AND p.rows > 0
        ORDER BY p.partition_number;
    OPEN parts;
    FETCH NEXT FROM parts INTO @pn, @rows, @b;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = CONCAT('archive partition ', @pn, ' (< ', CONVERT(char(10), @b, 120), '): ', @rows, ' rows');
        PRINT CONCAT(IIF(@DryRun = 1, 'dry-run: ', 'exec: '), @msg);
        IF @DryRun = 0
        BEGIN
            BEGIN TRANSACTION;
            -- SWITCH: метаданные, мгновенно; stage-секция должна быть пуста
            SET @sql = CONCAT(N'TRUNCATE TABLE ship.TrackingEventStage WITH (PARTITIONS (', @pn, N')); ',
                              N'ALTER TABLE ship.TrackingEvent SWITCH PARTITION ', @pn, N' TO ship.TrackingEventStage PARTITION ', @pn, N';');
            EXEC sys.sp_executesql @sql;
            -- В архив: одним INSERT (>= 102 400 строк попадают сразу в сжатые сегменты; меньше — в delta store, затем REORGANIZE)
            INSERT INTO ship.TrackingEventArchive WITH (TABLOCK)
                   (EventId, ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description, RawPayload)
            SELECT EventId, ShipmentId, CarrierId, ExternalEventId, StatusId, OccurredAt, ReceivedAt, LocationText, LocationPostalCode, Description, RawPayload
            FROM ship.TrackingEventStage WHERE $PARTITION.pf_MonthlyEvents(OccurredAt) = @pn;
            SET @sql = CONCAT(N'TRUNCATE TABLE ship.TrackingEventStage WITH (PARTITIONS (', @pn, N'));');
            EXEC sys.sp_executesql @sql;
            COMMIT;
        END;
        FETCH NEXT FROM parts INTO @pn, @rows, @b;
    END;
    CLOSE parts; DEALLOCATE parts;

    /* 3. MERGE: убрать самые левые пустые границы (обе секции вокруг границы пусты — движения данных нет) */
    DECLARE @leftBound datetime2(3);
    WHILE 1 = 1
    BEGIN
        SET @leftBound = (SELECT MIN(CAST(value AS datetime2(3))) FROM sys.partition_range_values AS v
                          JOIN sys.partition_functions AS f ON f.function_id = v.function_id WHERE f.name = N'pf_MonthlyEvents');
        IF @leftBound IS NULL OR @leftBound > @cutoff BREAK;
        IF EXISTS (SELECT 1 FROM sys.partitions AS p JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
                   WHERE p.object_id IN (OBJECT_ID(N'ship.TrackingEvent'), OBJECT_ID(N'ship.TrackingEventStage')) AND i.index_id = 1
                     AND p.partition_number <= 2 AND p.rows > 0) BREAK;   -- не пусто — не трогаем
        SET @sql = CONCAT(N'ALTER PARTITION FUNCTION pf_MonthlyEvents() MERGE RANGE (''', CONVERT(char(10), @leftBound, 120), N''');');
        PRINT CONCAT(IIF(@DryRun = 1, 'dry-run: ', 'exec: '), @sql);
        IF @DryRun = 0 EXEC sys.sp_executesql @sql; ELSE BREAK;
    END;

    IF @DryRun = 0
    BEGIN
        ALTER INDEX CCI_TrackingEventArchive ON ship.TrackingEventArchive REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);
        -- Нижняя граница горячего окна → ingest отклоняет более старые события как 'too-old'
        DECLARE @windowStart datetime2(3) = (SELECT MIN(CAST(value AS datetime2(3))) FROM sys.partition_range_values AS v
                                             JOIN sys.partition_functions AS f ON f.function_id = v.function_id WHERE f.name = N'pf_MonthlyEvents');
        MERGE ops.Setting AS t USING (SELECT 'ingest.hot_window_start' AS Name, CONVERT(nvarchar(30), @windowStart, 126) AS Value) AS s ON t.Name = s.Name
        WHEN MATCHED THEN UPDATE SET Value = s.Value, UpdatedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (Name, Value) VALUES (s.Name, s.Value);
    END;
END;
GO

-- diagnostic: safe to re-run
EXEC ops.usp_MaintainEventPartitions @MonthsAhead = 2, @RetainMonths = 12, @DryRun = 1;

-- Состояние секций горячей таблицы, stage и архива
SELECT OBJECT_NAME(p.object_id) AS table_name, p.partition_number, p.rows
FROM sys.partitions AS p WHERE p.object_id IN (OBJECT_ID(N'ship.TrackingEvent'), OBJECT_ID(N'ship.TrackingEventStage')) AND p.index_id = 1 AND p.rows > 0
ORDER BY table_name, p.partition_number;
SELECT COUNT_BIG(*) AS archived_rows, MIN(OccurredAt) AS from_at, MAX(OccurredAt) AS to_at FROM ship.TrackingEventArchive;
GO
