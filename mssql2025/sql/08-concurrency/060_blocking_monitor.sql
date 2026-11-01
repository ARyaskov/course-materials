-- diagnostic: safe to re-run
/*
  060_blocking_monitor.sql — блокировки текущих сессий, цепочка «кто кого ждёт», эскалации, ожидания LCK (урок 8.3).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Блокировки всех пользовательских сессий с расшифровкой объекта и индекса
SELECT tl.request_session_id, tl.resource_type, tl.request_mode, tl.request_status, tl.resource_description,
       COALESCE(OBJECT_NAME(p.object_id), OBJECT_NAME(tl.resource_associated_entity_id)) AS object_name, i.name AS index_name
FROM sys.dm_tran_locks AS tl
LEFT JOIN sys.partitions AS p ON p.hobt_id = tl.resource_associated_entity_id AND tl.resource_type IN ('KEY', 'PAGE', 'HOBT')
LEFT JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE tl.resource_database_id = DB_ID() AND tl.request_session_id <> @@SPID AND tl.resource_type <> 'DATABASE'
ORDER BY tl.request_session_id, tl.resource_type;

-- 2. Кто кого ждёт: тексты обеих сторон
SELECT r.session_id AS waiting, r.blocking_session_id AS blocker, r.wait_type, r.wait_time, r.wait_resource,
       (SELECT text FROM sys.dm_exec_sql_text(r.sql_handle)) AS waiting_sql,
       (SELECT text FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS blocker_last_sql,
       bs.open_transaction_count AS blocker_open_tran, bs.last_request_end_time AS blocker_idle_since, bs.program_name AS blocker_program
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS bs ON bs.session_id = r.blocking_session_id
JOIN sys.dm_exec_connections AS c ON c.session_id = r.blocking_session_id
WHERE r.blocking_session_id <> 0;

-- 3. Эскалации по индексам
SELECT OBJECT_NAME(ios.object_id) AS table_name, i.name, ios.index_lock_promotion_attempt_count, ios.index_lock_promotion_count,
       ios.row_lock_wait_count, ios.row_lock_wait_in_ms
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios
JOIN sys.indexes AS i ON i.object_id = ios.object_id AND i.index_id = ios.index_id
WHERE ios.index_lock_promotion_attempt_count > 0 OR ios.row_lock_wait_count > 0
ORDER BY ios.row_lock_wait_in_ms DESC;

-- 4. Ожидания блокировок с момента старта
SELECT wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms
FROM sys.dm_os_wait_stats WHERE wait_type LIKE N'LCK_M_%' AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

-- 5. Память под блокировки
SELECT type, pages_kb FROM sys.dm_os_memory_clerks WHERE type = N'OBJECTSTORE_LOCK_MANAGER';
GO
