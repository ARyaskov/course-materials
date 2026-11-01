/* 09-performance/010_query_store.sql
   Query Store: рабочие настройки, автоматическая коррекция планов, database scoped configuration для IQP 2025,
   представления ops.vw_QueryStore* для повседневного чтения. Идемпотентен.
*/
USE master;
GO
ALTER DATABASE Waybill SET QUERY_STORE = ON;
ALTER DATABASE Waybill SET QUERY_STORE
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,                 -- не захватывать одноразовые дешёвые запросы
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 15,              -- гранулярность агрегатов runtime stats
    MAX_STORAGE_SIZE_MB = 1024,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200,
    WAIT_STATS_CAPTURE_MODE = ON
);
-- Автоматическая коррекция: если новый план хуже последнего хорошего — вернуть последний хороший
ALTER DATABASE Waybill SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
GO

USE Waybill;
GO
SET NOCOUNT ON;
GO

-- IQP: настройки уровня базы (compat 170 включает большинство по умолчанию; фиксируем явно)
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
ALTER DATABASE SCOPED CONFIGURATION SET OPTIMIZED_SP_EXECUTESQL = ON;         -- 2025: один план для одинакового текста sp_executesql
ALTER DATABASE SCOPED CONFIGURATION SET DOP_FEEDBACK = ON;
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK = ON;
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = ON;
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT = ON;
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;            -- sys.dm_exec_query_plan_stats: последний фактический план
BEGIN TRY
    EXEC sys.sp_executesql N'ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_PLAN_OPTIMIZATION = ON;';   -- 2025: планы для @p IS NULL OR col = @p
END TRY
BEGIN CATCH
    PRINT CONCAT('OPTIONAL_PARAMETER_PLAN_OPTIMIZATION недоступна в этой сборке: ', ERROR_MESSAGE());
END CATCH;
GO

SELECT actual_state_desc, query_capture_mode_desc, interval_length_minutes, max_storage_size_mb, current_storage_size_mb,
       stale_query_threshold_days, wait_stats_capture_mode_desc, size_based_cleanup_mode_desc
FROM sys.database_query_store_options;

SELECT name, value FROM sys.database_scoped_configurations
WHERE name IN (N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION', N'OPTIMIZED_SP_EXECUTESQL', N'DOP_FEEDBACK', N'CE_FEEDBACK',
               N'MEMORY_GRANT_FEEDBACK_PERSISTENCE', N'MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT', N'OPTIONAL_PARAMETER_PLAN_OPTIMIZATION',
               N'LAST_QUERY_PLAN_STATS');

SELECT name, desired_state_desc, actual_state_desc, reason_desc FROM sys.database_automatic_tuning_options;
GO

-- Самые дорогие запросы за последние N часов: по CPU, с числом планов и текстом
CREATE OR ALTER VIEW ops.vw_QueryStoreTop
AS
SELECT TOP (50)
       q.query_id,
       COUNT(DISTINCT p.plan_id)                     AS plans,
       SUM(rs.count_executions)                      AS executions,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS decimal(18, 1))      AS total_cpu_ms,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(18, 2)) AS avg_cpu_ms,
       CAST(SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(18, 2)) AS avg_duration_ms,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS decimal(18, 0)) AS avg_reads,
       MAX(rs.last_execution_time)                   AS last_executed,
       OBJECT_SCHEMA_NAME(q.object_id) + '.' + OBJECT_NAME(q.object_id) AS object_name,
       LEFT(qt.query_sql_text, 400)                  AS query_text
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY q.query_id, q.object_id, qt.query_sql_text
ORDER BY total_cpu_ms DESC;
GO

-- Регрессии: запросы, у которых свежий план медленнее предыдущего в 2 и более раз
CREATE OR ALTER VIEW ops.vw_QueryStoreRegressions
AS
WITH per_plan AS
(
    SELECT p.query_id, p.plan_id, p.is_forced_plan,
           SUM(rs.count_executions) AS executions,
           SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS avg_cpu_ms,
           MIN(rs.first_execution_time) AS first_seen, MAX(rs.last_execution_time) AS last_seen
    FROM sys.query_store_plan AS p
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= DATEADD(DAY, -7, SYSUTCDATETIME())
    GROUP BY p.query_id, p.plan_id, p.is_forced_plan
),
ranked AS
(
    SELECT *, ROW_NUMBER() OVER (PARTITION BY query_id ORDER BY last_seen DESC) AS rn_recent
    FROM per_plan
)
SELECT TOP (50)
       cur.query_id, cur.plan_id AS current_plan, prev.plan_id AS previous_plan,
       CAST(cur.avg_cpu_ms AS decimal(18, 2)) AS current_avg_cpu_ms, CAST(prev.avg_cpu_ms AS decimal(18, 2)) AS previous_avg_cpu_ms,
       CAST(cur.avg_cpu_ms / NULLIF(prev.avg_cpu_ms, 0) AS decimal(9, 1)) AS slowdown_x,
       cur.executions AS current_executions, prev.executions AS previous_executions,
       cur.is_forced_plan,
       LEFT(qt.query_sql_text, 300) AS query_text
FROM ranked AS cur
JOIN ranked AS prev ON prev.query_id = cur.query_id AND prev.rn_recent = 2
JOIN sys.query_store_query AS q ON q.query_id = cur.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE cur.rn_recent = 1
  AND cur.executions >= 10 AND prev.executions >= 10
  AND cur.avg_cpu_ms >= 2 * prev.avg_cpu_ms
ORDER BY slowdown_x DESC;
GO

-- Ожидания по запросам из Query Store (WAIT_STATS_CAPTURE_MODE = ON)
CREATE OR ALTER VIEW ops.vw_QueryStoreWaits
AS
SELECT TOP (50)
       ws.plan_id, p.query_id, ws.wait_category_desc,
       CAST(SUM(ws.total_query_wait_time_ms) AS bigint) AS total_wait_ms,
       CAST(AVG(ws.avg_query_wait_time_ms) AS decimal(18, 2)) AS avg_wait_ms,
       LEFT(qt.query_sql_text, 200) AS query_text
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_plan AS p ON p.plan_id = ws.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
WHERE i.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY ws.plan_id, p.query_id, ws.wait_category_desc, qt.query_sql_text
ORDER BY total_wait_ms DESC;
GO

-- Форсированные планы и их состояние (failure_count > 0 — план не удаётся применить; см. force_failure_count / last_force_failure_reason_desc)
CREATE OR ALTER VIEW ops.vw_QueryStoreForced
AS
SELECT p.query_id, p.plan_id, p.is_forced_plan, p.force_failure_count, p.last_force_failure_reason_desc,
       p.plan_forcing_type_desc, p.engine_version, p.compatibility_level, p.last_execution_time,
       LEFT(qt.query_sql_text, 200) AS query_text
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE p.is_forced_plan = 1;
GO

/* Ручное форсирование (значения query_id / plan_id берутся из представлений выше):
   EXEC sys.sp_query_store_force_plan   @query_id = 42, @plan_id = 7;
   EXEC sys.sp_query_store_unforce_plan @query_id = 42, @plan_id = 7;
   Рекомендации автоматической коррекции: SELECT reason, score, details FROM sys.dm_db_tuning_recommendations;
*/
SELECT 'query store' AS component, (SELECT COUNT(*) FROM sys.query_store_query) AS queries, (SELECT COUNT(*) FROM sys.query_store_plan) AS plans;
GO
