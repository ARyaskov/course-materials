-- diagnostic: safe to re-run
/*
  045_long_transactions.sql — долгие транзакции, журнал, PVS (урок 8.8).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Активные транзакции с состоянием сессии и объёмом журнала
SELECT at.transaction_id, at.name, at.transaction_begin_time,
       DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) AS age_seconds,
       st.session_id, s.login_name, s.program_name, s.host_name,
       CASE WHEN r.session_id IS NULL THEN 'idle (sleeping)' ELSE r.status END AS session_state,
       dt.database_transaction_log_record_count AS log_records,
       dt.database_transaction_log_bytes_used / 1024 AS log_kb,
       (SELECT text FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS last_sql
FROM sys.dm_tran_active_transactions AS at
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = at.transaction_id
JOIN sys.dm_tran_database_transactions AS dt ON dt.transaction_id = at.transaction_id AND dt.database_id = DB_ID()
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
JOIN sys.dm_exec_connections AS c ON c.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = st.session_id
ORDER BY at.transaction_begin_time;

-- 2. Журнал: причина невозможности усечения, размер, VLF
SELECT d.name, d.recovery_model_desc, d.log_reuse_wait_desc, ls.total_log_size_mb, ls.active_log_size_mb, ls.total_vlf_count, ls.active_vlf_count,
       ls.log_truncation_holdup_reason
FROM sys.databases AS d CROSS APPLY sys.dm_db_log_stats(d.database_id) AS ls
WHERE d.name = N'Waybill';

-- 3. Persistent version store (ADR)
SELECT persistent_version_store_size_kb / 1024 AS pvs_mb, online_index_version_store_size_kb / 1024 AS online_index_mb,
       current_aborted_transaction_count, oldest_active_transaction_id,
       aborted_version_cleaner_start_time, aborted_version_cleaner_end_time
FROM sys.dm_tran_persistent_version_store_stats WHERE database_id = DB_ID();

-- 4. Snapshot-транзакции, удерживающие версии
SELECT ast.transaction_id, ast.session_id, ast.elapsed_time_seconds, ast.first_snapshot_sequence_num, s.program_name
FROM sys.dm_tran_active_snapshot_database_transactions AS ast
JOIN sys.dm_exec_sessions AS s ON s.session_id = ast.session_id
ORDER BY ast.elapsed_time_seconds DESC;
GO
