-- diagnostic: safe to re-run
/*
  020_whats_running.sql — «кто что делает прямо сейчас» и топ ожиданий (урок 1.7).
*/
SET NOCOUNT ON;
GO

-- 1. Активные запросы с текстом текущей инструкции, ожиданием и блокировщиком
SELECT
    r.session_id,
    s.login_name,
    s.program_name,
    s.host_name,
    DB_NAME(r.database_id)   AS database_name,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time                AS wait_ms,
    r.blocking_session_id,
    r.cpu_time                 AS cpu_ms,
    r.total_elapsed_time       AS elapsed_ms,
    r.logical_reads,
    r.open_transaction_count,
    SUBSTRING(t.text,
              (r.statement_start_offset / 2) + 1,
              ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END
                - r.statement_start_offset) / 2) + 1) AS current_statement,
    qp.query_plan
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;

-- 2. Сессии с открытой транзакцией, которые ничего не выполняют («ушли думать»)
SELECT s.session_id, s.login_name, s.program_name, s.host_name, s.open_transaction_count,
       s.last_request_start_time, s.last_request_end_time,
       DATEDIFF(SECOND, s.last_request_end_time, SYSDATETIME()) AS idle_seconds
FROM sys.dm_exec_sessions AS s
WHERE s.is_user_process = 1
  AND s.open_transaction_count > 0
  AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests AS r WHERE r.session_id = s.session_id)
ORDER BY idle_seconds DESC;

-- 3. Цепочки блокировок: корень (никого не ждёт) → кто его ждёт
WITH chain AS
(
    SELECT session_id, blocking_session_id, 0 AS level, CAST(session_id AS varchar(1000)) AS path
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0 AND session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests)
    UNION ALL
    SELECT r.session_id, r.blocking_session_id, c.level + 1, CAST(c.path + ' -> ' + CAST(r.session_id AS varchar(10)) AS varchar(1000))
    FROM sys.dm_exec_requests AS r
    JOIN chain AS c ON c.session_id = r.blocking_session_id
)
SELECT * FROM chain ORDER BY path;

-- 4. Топ ожиданий с момента старта (без фоновых)
SELECT TOP (15)
    wait_type,
    waiting_tasks_count,
    wait_time_ms / 1000.0                          AS wait_s,
    (wait_time_ms - signal_wait_time_ms) / 1000.0  AS resource_wait_s,
    signal_wait_time_ms / 1000.0                   AS signal_wait_s,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS decimal(5, 2)) AS pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    N'SLEEP_TASK', N'BROKER_TO_FLUSH', N'BROKER_TASK_STOP', N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR',
    N'LAZYWRITER_SLEEP', N'SQLTRACE_BUFFER_FLUSH', N'XE_TIMER_EVENT', N'XE_DISPATCHER_WAIT', N'FT_IFTS_SCHEDULER_IDLE_WAIT',
    N'LOGMGR_QUEUE', N'CHECKPOINT_QUEUE', N'REQUEST_FOR_DEADLOCK_SEARCH', N'DIRTY_PAGE_POLL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    N'SP_SERVER_DIAGNOSTICS_SLEEP', N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
    N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'PVS_PREALLOCATE', N'SOS_WORK_DISPATCHER',
    N'ONDEMAND_TASK_QUEUE', N'WAITFOR', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_SYSTEMTASK', N'VDI_CLIENT_OTHER')
ORDER BY wait_time_ms DESC;
GO
