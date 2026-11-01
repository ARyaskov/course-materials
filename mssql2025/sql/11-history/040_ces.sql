/* 11-history/040_ces.sql
   Change Event Streaming (SQL Server 2025, preview): публикация изменений ship.Shipment в Azure Event Hubs (AMQP / Kafka-совместимая точка).
   Включается только при заданных настройках ops.Setting: 'ces.destination' (hostname/hub) и 'ces.credential' (имя database scoped credential).
   Без них — печатает, что нужно, и выводит состояние. Все обращения к объектам CES — динамические: скрипт выполняется и на сборках без CES.
   Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

DECLARE @dest nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'ces.destination');
DECLARE @cred sysname       = (SELECT Value FROM ops.Setting WHERE Name = 'ces.credential');
DECLARE @available bit = IIF(OBJECT_ID(N'sys.sp_create_event_stream_group') IS NOT NULL, 1, 0);

IF @available = 0
    PRINT 'CES: в этой сборке отсутствует sys.sp_create_event_stream_group — функция недоступна';
ELSE IF @dest IS NULL OR @cred IS NULL
BEGIN
    PRINT 'CES: не настроено. Для включения:';
    PRINT '  1) CREATE MASTER KEY (если нет); CREATE DATABASE SCOPED CREDENTIAL ces_eventhubs WITH IDENTITY = ''SHARED ACCESS SIGNATURE'', SECRET = ''<policy-name>;<sas-key>'';';
    PRINT '  2) INSERT INTO ops.Setting (Name, Value) VALUES (''ces.destination'', ''<namespace>.servicebus.windows.net/<hub>''), (''ces.credential'', ''ces_eventhubs'');';
    PRINT '  3) повторить скрипт';
END;
ELSE
BEGIN
    DECLARE @sql nvarchar(max) = N'
    -- 1. Включить CES на базе (идемпотентно: повторный вызов — ошибка, поэтому проверяем каталог)
    IF NOT EXISTS (SELECT 1 FROM sys.event_stream_groups)
       AND NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_event_stream_enabled = 1)
        EXEC sys.sp_enable_event_stream;

    -- 2. Группа потока: назначение, учётные данные, ключ секционирования
    IF NOT EXISTS (SELECT 1 FROM sys.event_stream_groups WHERE name = N''waybill-shipments'')
        EXEC sys.sp_create_event_stream_group
             @stream_group_name = N''waybill-shipments'',
             @destination_type = N''AzureEventHubsAmqp'',
             @destination_location = @dest,
             @destination_credential = @cred,
             @max_message_size_kb = 512,
             @partition_key_scheme = N''PrimaryKey'';     -- события одного отправления — в одну партицию (порядок)

    -- 3. Таблица в группе
    IF NOT EXISTS (SELECT 1 FROM sys.event_stream_objects WHERE object_id = OBJECT_ID(N''ship.Shipment''))
        EXEC sys.sp_add_object_to_event_stream_group
             @stream_group_name = N''waybill-shipments'',
             @object_name = N''ship.Shipment'',
             @include_old_values = 1,                     -- before/after в сообщении
             @include_all_columns = 0;                    -- только ключ и изменённые столбцы (без Attributes json)

    EXEC sys.sp_start_event_stream_group @stream_group_name = N''waybill-shipments'';';
    EXEC sys.sp_executesql @sql, N'@dest nvarchar(400), @cred sysname', @dest = @dest, @cred = @cred;
END;
GO

-- diagnostic: safe to re-run (каталог и DMV CES, если есть)
IF OBJECT_ID(N'sys.event_stream_groups') IS NOT NULL
    EXEC sys.sp_executesql N'
        SELECT * FROM sys.event_stream_groups;
        SELECT * FROM sys.event_stream_objects;
        SELECT TOP (5) * FROM sys.dm_change_feed_log_scan_sessions ORDER BY 1 DESC;
        SELECT TOP (10) * FROM sys.dm_change_feed_errors ORDER BY 1 DESC;';
ELSE
    PRINT 'CES: каталог sys.event_stream_groups отсутствует';
GO
