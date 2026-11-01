-- diagnostic: safe to re-run
/*
  025_json_read_demo.sql — чтение файлов webhook через OPENROWSET(BULK ..., SINGLE_CLOB), JSON_VALUE/JSON_QUERY/JSON_PATH_EXISTS (урок 5.2).
  Путь к файлам — на стороне сервера. Windows-экземпляр: папка проекта data/webhooks; контейнер: /import/webhooks.
  Если путь недоступен, блок печатает ошибку и не останавливает apply.ps1.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Windows: разместите учебные файлы в C:\Waybill\data или укажите свой серверный путь.
DECLARE @dir nvarchar(260) = CASE WHEN (SELECT host_platform FROM sys.dm_os_host_info) = N'Linux'
                                THEN N'/import/webhooks/' ELSE N'C:\Waybill\data\webhooks\' END;
DECLARE @files TABLE (carrier varchar(16), name nvarchar(50));
INSERT INTO @files VALUES ('FASTEX', N'fastex.json'), ('NORDPOST', N'nordpost.json'), ('CITYRUN', N'cityrun.json'), ('CITYRUN', N'broken.json');

DECLARE @carrier varchar(16), @name nvarchar(50), @sql nvarchar(max);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT carrier, name FROM @files;
OPEN cur; FETCH NEXT FROM cur INTO @carrier, @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    DECLARE @doc json = TRY_CAST((SELECT BulkColumn FROM OPENROWSET(BULK ' + QUOTENAME(@dir + @name, '''') + N', SINGLE_CLOB) AS f) AS json);
    SELECT ' + QUOTENAME(@name, '''') + N' AS file_name, ISJSON(@doc) AS is_json,
           COALESCE(JSON_VALUE(@doc, ''$.events[0].tracking''), JSON_VALUE(@doc, ''$.shipment.trackingNumber''), JSON_VALUE(@doc, ''$.tracking_no'')) AS tracking,
           COALESCE(JSON_VALUE(@doc, ''$.events[0].id''), JSON_VALUE(@doc, ''$.shipment.events.event[0].eventId''), JSON_VALUE(@doc, ''$.event_id'')) AS external_event_id,
           COALESCE(JSON_VALUE(@doc, ''$.events[0].status''), JSON_VALUE(@doc, ''$.shipment.events.event[0].code''), JSON_VALUE(@doc, ''$.state'')) AS external_status,
           COALESCE(TRY_CAST(JSON_VALUE(@doc, ''$.events[0].time'') AS datetime2(3)),
                    CAST(TRY_CAST(JSON_VALUE(@doc, ''$.shipment.events.event[0].timestamp'') AS datetimeoffset(0)) AT TIME ZONE ''UTC'' AS datetime2(3)),
                    TRY_CAST(JSON_VALUE(@doc, ''$.occurred'') AS datetime2(3))) AS occurred_utc,
           JSON_PATH_EXISTS(@doc, ''$.events'') AS is_array_format, JSON_PATH_EXISTS(@doc, ''$.shipment'') AS is_nested_format;';
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT CONCAT(@name, ': ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM cur INTO @carrier, @name;
END;
CLOSE cur; DEALLOCATE cur;
GO

-- lax против strict на документе без времени
DECLARE @noTime json = N'{"tracking_no":"CR-2026-000099","event_id":"cr-9","state":"PICKED_UP"}';
SELECT JSON_VALUE(@noTime, 'lax $.occurred') AS lax_result;
BEGIN TRY
    SELECT JSON_VALUE(@noTime, 'strict $.occurred') AS strict_result;
END TRY
BEGIN CATCH
    PRINT CONCAT('strict: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
GO
