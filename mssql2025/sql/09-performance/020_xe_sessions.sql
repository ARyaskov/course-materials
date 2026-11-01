/* 09-performance/020_xe_sessions.sql
   Сессии Extended Events проекта: долгие запросы, таймауты клиента, deadlock-и, заблокированные процессы.
   Файловые цели пишутся в каталог журналов экземпляра (\Log или /var/opt/mssql/log). Идемпотентен.
*/
USE master;
GO
SET NOCOUNT ON;
GO

-- 1. Долгие запросы (> 1 с) в базе Waybill: текст, план-хэш, сессия, ожидания
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'waybill_long_queries')
    CREATE EVENT SESSION waybill_long_queries ON SERVER
    ADD EVENT sqlserver.rpc_completed
    (
        ACTION (sqlserver.sql_text, sqlserver.session_id, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.query_hash, sqlserver.query_plan_hash, sqlserver.username)
        WHERE sqlserver.database_name = N'Waybill' AND duration > 1000000     -- микросекунды
    ),
    ADD EVENT sqlserver.sql_batch_completed
    (
        ACTION (sqlserver.sql_text, sqlserver.session_id, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.query_hash, sqlserver.query_plan_hash, sqlserver.username)
        WHERE sqlserver.database_name = N'Waybill' AND duration > 1000000
    )
    ADD TARGET package0.event_file (SET filename = N'waybill_long_queries.xel', max_file_size = 50, max_rollover_files = 4)
    WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 5 SECONDS, STARTUP_STATE = ON);
GO

-- 2. Таймауты и отмены со стороны клиента (attention): что именно клиент не дождался
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'waybill_timeouts')
    CREATE EVENT SESSION waybill_timeouts ON SERVER
    ADD EVENT sqlserver.attention
    (
        ACTION (sqlserver.sql_text, sqlserver.session_id, sqlserver.client_app_name, sqlserver.client_hostname, sqlserver.username)
        WHERE sqlserver.database_name = N'Waybill'
    )
    ADD TARGET package0.ring_buffer (SET max_memory = 4096)
    WITH (STARTUP_STATE = ON);
GO

-- 3. Deadlock-и: свой файл, чтобы не зависеть от ротации system_health
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'waybill_deadlocks')
    CREATE EVENT SESSION waybill_deadlocks ON SERVER
    ADD EVENT sqlserver.xml_deadlock_report
    ADD TARGET package0.event_file (SET filename = N'waybill_deadlocks.xel', max_file_size = 50, max_rollover_files = 4)
    WITH (STARTUP_STATE = ON);
GO

-- 4. Блокировки дольше порога: blocked process report (порог — sp_configure, секунды)
EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;
EXEC sys.sp_configure N'blocked process threshold (s)', 5; RECONFIGURE;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'waybill_blocked')
    CREATE EVENT SESSION waybill_blocked ON SERVER
    ADD EVENT sqlserver.blocked_process_report
    (
        WHERE sqlserver.database_name = N'Waybill'
    )
    ADD TARGET package0.event_file (SET filename = N'waybill_blocked.xel', max_file_size = 50, max_rollover_files = 4)
    WITH (STARTUP_STATE = ON);
GO

-- Запуск всех сессий проекта (если ещё не запущены)
DECLARE @name sysname, @sql nvarchar(400);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name FROM sys.server_event_sessions AS s
    WHERE s.name LIKE N'waybill[_]%' AND NOT EXISTS (SELECT 1 FROM sys.dm_xe_sessions AS a WHERE a.name = s.name);
OPEN c;
FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CONCAT(N'ALTER EVENT SESSION ', QUOTENAME(@name), N' ON SERVER STATE = START;');
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM c INTO @name;
END;
CLOSE c; DEALLOCATE c;
GO

SELECT s.name, IIF(a.name IS NULL, 'stopped', 'running') AS state, s.startup_state
FROM sys.server_event_sessions AS s LEFT JOIN sys.dm_xe_sessions AS a ON a.name = s.name
WHERE s.name LIKE N'waybill[_]%';
GO

USE Waybill;
GO

-- Чтение долгих запросов из файла
CREATE OR ALTER VIEW ops.vw_XeLongQueries
AS
SELECT x.value('(/event/@timestamp)[1]', 'datetime2(3)')                                   AS event_time_utc,
       x.value('(/event/@name)[1]', 'sysname')                                              AS event_name,
       x.value('(/event/data[@name="duration"]/value)[1]', 'bigint') / 1000                 AS duration_ms,
       x.value('(/event/data[@name="cpu_time"]/value)[1]', 'bigint') / 1000                 AS cpu_ms,
       x.value('(/event/data[@name="logical_reads"]/value)[1]', 'bigint')                   AS logical_reads,
       x.value('(/event/data[@name="row_count"]/value)[1]', 'bigint')                       AS row_count,
       x.value('(/event/action[@name="session_id"]/value)[1]', 'int')                       AS session_id,
       x.value('(/event/action[@name="client_app_name"]/value)[1]', 'nvarchar(128)')        AS app,
       x.value('(/event/action[@name="query_hash"]/value)[1]', 'decimal(20)')               AS query_hash,
       x.value('(/event/action[@name="query_plan_hash"]/value)[1]', 'decimal(20)')          AS query_plan_hash,
       x.value('(/event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)')               AS sql_text
FROM (SELECT CAST(event_data AS xml) AS x FROM sys.fn_xe_file_target_read_file(N'waybill_long_queries*.xel', NULL, NULL, NULL)) AS t;
GO

-- Чтение таймаутов из ring_buffer
CREATE OR ALTER VIEW ops.vw_XeTimeouts
AS
SELECT e.value('(/event/@timestamp)[1]', 'datetime2(3)')                            AS event_time_utc,
       e.value('(/event/data[@name="duration"]/value)[1]', 'bigint') / 1000         AS waited_ms,
       e.value('(/event/action[@name="session_id"]/value)[1]', 'int')               AS session_id,
       e.value('(/event/action[@name="client_app_name"]/value)[1]', 'nvarchar(128)') AS app,
       e.value('(/event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)')        AS sql_text
FROM (SELECT CAST(t.target_data AS xml) AS x
      FROM sys.dm_xe_sessions AS s JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
      WHERE s.name = N'waybill_timeouts' AND t.target_name = N'ring_buffer') AS rb
CROSS APPLY rb.x.nodes('//RingBufferTarget/event') AS n (e);
GO

-- Чтение deadlock-ов: граф целиком + жертва
CREATE OR ALTER VIEW ops.vw_XeDeadlocks
AS
SELECT x.value('(/event/@timestamp)[1]', 'datetime2(3)')                                                  AS event_time_utc,
       x.value('(data/value/deadlock/victim-list/victimProcess/@id)[1]', 'varchar(40)')            AS victim,
       x.query('data/value/deadlock')                                                              AS deadlock_graph
FROM (SELECT CAST(event_data AS xml) AS x FROM sys.fn_xe_file_target_read_file(N'waybill_deadlocks*.xel', NULL, NULL, NULL)) AS t;
GO

-- Чтение blocked process report: кто и кого
CREATE OR ALTER VIEW ops.vw_XeBlocked
AS
SELECT x.value('(/event/@timestamp)[1]', 'datetime2(3)')                                                                    AS event_time_utc,
       x.value('(/event/data[@name="duration"]/value)[1]', 'bigint') / 1000000                                             AS blocked_s,
       x.value('(data/value/blocked-process-report/blocked-process/process/@spid)[1]', 'int')                        AS blocked_spid,
       x.value('(data/value/blocked-process-report/blocked-process/process/@waitresource)[1]', 'nvarchar(200)')      AS wait_resource,
       x.value('(data/value/blocked-process-report/blocked-process/process/inputbuf)[1]', 'nvarchar(max)')           AS blocked_sql,
       x.value('(data/value/blocked-process-report/blocking-process/process/@spid)[1]', 'int')                       AS blocking_spid,
       x.value('(data/value/blocked-process-report/blocking-process/process/@status)[1]', 'nvarchar(20)')            AS blocking_status,
       x.value('(data/value/blocked-process-report/blocking-process/process/inputbuf)[1]', 'nvarchar(max)')          AS blocking_sql
FROM (SELECT CAST(event_data AS xml) AS x FROM sys.fn_xe_file_target_read_file(N'waybill_blocked*.xel', NULL, NULL, NULL)) AS t;
GO

SELECT 'xe views' AS component, COUNT(*) AS views FROM sys.views WHERE schema_id = SCHEMA_ID(N'ops') AND name LIKE N'vw_Xe%';
GO
