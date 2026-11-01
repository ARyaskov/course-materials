/* 10-bulk/020_bulk_load.sql
   Массовая загрузка файлов перевозчиков: staging-heap ops.EventImport, ops.usp_ImportEventFile (BULK INSERT → TVP → ingest),
   загрузка JSON целиком через OPENROWSET(BULK … SINGLE_CLOB) в usp_ReceiveWebhook.
   Путь к файлам: ops.Setting 'import.root' (контейнер: /import; Windows: C:\Waybill\data или ваш серверный путь). Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Настройки уровня базы (первое использование: корень импорта)
IF OBJECT_ID(N'ops.Setting', N'U') IS NULL
    CREATE TABLE ops.Setting
    (
        Name      varchar(64)   NOT NULL CONSTRAINT PK_Setting PRIMARY KEY,
        Value     nvarchar(400) NOT NULL,
        UpdatedAt datetime2(3)  NOT NULL CONSTRAINT DF_Setting_UpdatedAt DEFAULT SYSUTCDATETIME()
    );
GO
-- Корень: контейнер монтирует ./data как /import; на Windows-экземпляре — каталог data проекта (замените путь под свой стенд)
INSERT INTO ops.Setting (Name, Value)
SELECT 'import.root', CASE WHEN (SELECT host_platform FROM sys.dm_os_host_info) = N'Linux' THEN N'/import'
                           ELSE N'C:\Waybill\data' END
WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'import.root');
GO

-- Staging: heap, все столбцы текстовые — файл загружается «как есть», проверка отдельно
IF OBJECT_ID(N'ops.EventImport', N'U') IS NULL
    CREATE TABLE ops.EventImport
    (
        ImportId        bigint        NOT NULL IDENTITY(1, 1),
        FileName        nvarchar(260) NOT NULL,
        TrackingNumber  varchar(64)   NULL,
        ExternalEventId varchar(64)   COLLATE Latin1_General_100_BIN2 NULL,
        ExternalStatus  varchar(32)   NULL,
        OccurredAtText  varchar(40)   NULL,
        LocationText    nvarchar(200) NULL,
        PostalCode      varchar(16)   NULL,
        Description     nvarchar(400) NULL,
        LoadedAt        datetime2(3)  NOT NULL CONSTRAINT DF_EventImport_LoadedAt DEFAULT SYSUTCDATETIME()
    );   -- heap без индексов: минимальное логирование при TABLOCK
GO

-- Промежуточная таблица под BULK INSERT: строго столбцы файла (identity и служебные столбцы мешают сопоставлению по позиции)
IF OBJECT_ID(N'ops.EventImportRaw', N'U') IS NULL
    CREATE TABLE ops.EventImportRaw
    (
        TrackingNumber  varchar(64)   NULL,
        ExternalEventId varchar(64)   COLLATE Latin1_General_100_BIN2 NULL,
        ExternalStatus  varchar(32)   NULL,
        OccurredAtText  varchar(40)   NULL,
        LocationText    nvarchar(200) NULL,
        PostalCode      varchar(16)   NULL,
        Description     nvarchar(400) NULL
    );
GO

CREATE OR ALTER PROCEDURE ops.usp_ImportEventFile
    @CarrierCode  varchar(16),
    @FileName     nvarchar(260),          -- относительно import.root, например N'events/nordpost-2026-08.csv'
    @DryRun       bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @root nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'import.root');
    DECLARE @sep nchar(1) = IIF(@root LIKE N'/%', N'/', N'\');
    DECLARE @path nvarchar(700) = CONCAT(@root, @sep, REPLACE(@FileName, N'/', @sep));
    DECLARE @errPath nvarchar(700) = CONCAT(@path, N'.', FORMAT(SYSUTCDATETIME(), 'yyyyMMdd-HHmmss-fff'), N'.errors');   -- BULK INSERT не перезаписывает существующий ERRORFILE
    DECLARE @sql nvarchar(max);

    -- 1. Файл → staging raw (heap): формат CSV, UTF-8, заголовок пропускаем, до 10 битых строк — в .errors
    TRUNCATE TABLE ops.EventImportRaw;
    SET @sql = CONCAT(N'BULK INSERT ops.EventImportRaw FROM ', QUOTENAME(@path, ''''), N'
        WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
              CODEPAGE = ''65001'', FIRSTROW = 2, BATCHSIZE = 100000, TABLOCK, MAXERRORS = 10, ERRORFILE = ', QUOTENAME(@errPath, ''''), N');');
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Ошибки преобразования отдельных строк (4863 усечение, 4864 тип, 4865 …) BULK INSERT не прерывают: строки уходят в ERRORFILE,
        -- загрузка завершается, но сообщение с severity 16 всё равно приходит — и без CATCH оно оборвало бы процедуру.
        -- Строка с неверным ЧИСЛОМ полей в режиме CSV — фатальна (не считается в MAXERRORS): файл не загрузится целиком.
        IF ERROR_NUMBER() NOT BETWEEN 4863 AND 4867 THROW;
        PRINT CONCAT('строки с ошибками преобразования записаны в ', @errPath, ': ', ERROR_MESSAGE());
    END CATCH
    DECLARE @loaded int = (SELECT COUNT(*) FROM ops.EventImportRaw);

    INSERT INTO ops.EventImport (FileName, TrackingNumber, ExternalEventId, ExternalStatus, OccurredAtText, LocationText, PostalCode, Description)
    SELECT @FileName, TrackingNumber, ExternalEventId, ExternalStatus, OccurredAtText, LocationText, PostalCode, Description
    FROM ops.EventImportRaw;

    -- 2. Преобразование: время с offset → UTC; всё, что не разобралось, — в ingest как есть (там получит 'bad-time')
    DECLARE @batch ops.tt_TrackingEventIn;
    INSERT INTO @batch (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, LocationText, LocationPostalCode, Description, RawFragment)
    SELECT r.TrackingNumber, r.ExternalEventId, r.ExternalStatus,
           ISNULL(CAST(SWITCHOFFSET(TRY_CAST(r.OccurredAtText AS datetimeoffset(3)), '+00:00') AS datetime2(3)), '1900-01-01'),
           LEFT(r.LocationText, 100), r.PostalCode, r.Description,
           JSON_OBJECT('line': CONCAT_WS(',', r.TrackingNumber, r.ExternalEventId COLLATE DATABASE_DEFAULT, r.ExternalStatus, r.OccurredAtText))   -- RawPayload — json: сырая строка файла как документ
    FROM ops.EventImportRaw AS r
    WHERE r.TrackingNumber IS NOT NULL AND r.ExternalEventId IS NOT NULL AND r.ExternalStatus IS NOT NULL;

    IF @DryRun = 1
    BEGIN
        SELECT @loaded AS loaded_rows, COUNT(*) AS batch_rows, SUM(IIF(OccurredAt = '1900-01-01', 1, 0)) AS bad_time_rows FROM @batch;
        RETURN;
    END;

    -- 3. Ingest: вся классификация, идемпотентность и смена статусов — в одной процедуре с webhook-ами
    DECLARE @inboxId bigint;
    INSERT INTO ops.WebhookInbox (CarrierId, BodyHash, Body, Status)
    SELECT c.CarrierId, HASHBYTES('SHA2_256', CONCAT(N'file:', @FileName, N':', SYSUTCDATETIME())), JSON_OBJECT('file': @FileName, 'rows': @loaded), 1
    FROM ref.Carrier AS c WHERE c.Code = @CarrierCode;
    IF @@ROWCOUNT = 0 THROW 50031, N'Неизвестный перевозчик', 1;
    SET @inboxId = SCOPE_IDENTITY();

    EXEC ops.usp_IngestTrackingEvents @CarrierCode = @CarrierCode, @Events = @batch, @InboxId = @inboxId;
END;
GO

-- JSON-файл целиком → тот же путь, что и HTTP-webhook
CREATE OR ALTER PROCEDURE ops.usp_ImportWebhookFile
    @CarrierCode varchar(16),
    @FileName    nvarchar(260)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @root nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'import.root');
    DECLARE @sep nchar(1) = IIF(@root LIKE N'/%', N'/', N'\');
    DECLARE @path nvarchar(700) = CONCAT(@root, @sep, REPLACE(@FileName, N'/', @sep));
    DECLARE @body nvarchar(max), @sql nvarchar(max) = CONCAT(N'SELECT @body = BulkColumn FROM OPENROWSET(BULK ', QUOTENAME(@path, ''''), N', SINGLE_CLOB) AS f;');
    EXEC sys.sp_executesql @sql, N'@body nvarchar(max) OUTPUT', @body = @body OUTPUT;
    EXEC ops.usp_ReceiveWebhook @CarrierCode = @CarrierCode, @Body = @body;
END;
GO

-- diagnostic: safe to re-run (файл загружается в staging; ingest — в транзакции с откатом)
BEGIN TRY
    EXEC ops.usp_ImportEventFile @CarrierCode = 'NORDPOST', @FileName = N'events/nordpost-2026-08.csv', @DryRun = 1;
    -- Ошибки преобразования (усечённое значение) — в файле *.errors и *.errors.Error.Txt рядом с исходным
    BEGIN TRANSACTION;
    EXEC ops.usp_ImportEventFile @CarrierCode = 'NORDPOST', @FileName = N'events/nordpost-2026-08.csv';
    SELECT Reason, COUNT(*) AS rejected FROM ops.RejectedEvent WHERE InboxId = (SELECT MAX(InboxId) FROM ops.WebhookInbox) GROUP BY Reason;
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT CONCAT('bulk load demo skipped: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());   -- нет прав ADMINISTER BULK OPERATIONS или неверный import.root
END CATCH;
GO
