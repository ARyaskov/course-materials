/*
  050_query_store_baseline.sql — сравнение производительности до/после деплоя по Query Store (глава 16).

  ops.usp_QueryStoreBaseline @Label — снимок топ-200 запросов за последние сутки (по CPU): query_hash, текст, executions,
    avg cpu/duration/reads → ops.QueryStoreBaseline.
  ops.tvf_QueryStoreCompare @BaselineLabel, @Threshold — запросы, у которых средняя длительность или чтения выросли более чем
    в @Threshold раз относительно снимка (по query_hash: текст один и тот же, план мог смениться).
  CI: снимок 'before' → smoke-нагрузка → 'after' → сравнение → артефакт.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.QueryStoreBaseline', N'U') IS NULL
CREATE TABLE ops.QueryStoreBaseline
(
    BaselineId    int IDENTITY CONSTRAINT PK_QueryStoreBaseline PRIMARY KEY,
    TakenAt       datetime2(0) NOT NULL CONSTRAINT DF_QueryStoreBaseline_TakenAt DEFAULT SYSUTCDATETIME(),
    Label         varchar(32)  NOT NULL,
    QueryHash     binary(8)    NOT NULL,
    QueryId       bigint       NOT NULL,
    ObjectName    nvarchar(260) NULL,
    QueryText     nvarchar(max) NOT NULL,
    Executions    bigint       NOT NULL,
    AvgCpuMs      decimal(12, 3) NOT NULL,
    AvgDurationMs decimal(12, 3) NOT NULL,
    AvgReads      decimal(14, 1) NOT NULL,
    PlanCount     int          NOT NULL,
    INDEX IX_QueryStoreBaseline_Label (Label, TakenAt) INCLUDE (QueryHash)
);
GO

CREATE OR ALTER PROCEDURE ops.usp_QueryStoreBaseline @Label varchar(32) = 'before', @Top int = 200, @Hours int = 24
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @since datetimeoffset = DATEADD(hour, -@Hours, SYSDATETIMEOFFSET());
    INSERT INTO ops.QueryStoreBaseline (Label, QueryHash, QueryId, ObjectName, QueryText, Executions, AvgCpuMs, AvgDurationMs, AvgReads, PlanCount)
    SELECT TOP (@Top) @Label, q.query_hash, q.query_id,
           IIF(q.object_id = 0, NULL, OBJECT_SCHEMA_NAME(q.object_id) + N'.' + OBJECT_NAME(q.object_id)),
           qt.query_sql_text,
           SUM(rs.count_executions),
           CAST(SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(12, 3)),
           CAST(SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(12, 3)),
           CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS decimal(14, 1)),
           COUNT(DISTINCT p.plan_id)
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE i.start_time >= @since AND qt.query_sql_text NOT LIKE N'%query_store%'
    GROUP BY q.query_hash, q.query_id, q.object_id, qt.query_sql_text
    ORDER BY SUM(rs.avg_cpu_time * rs.count_executions) DESC;
    PRINT CONCAT('baseline ', @Label, ': ', @@ROWCOUNT, ' queries');
END;
GO

CREATE OR ALTER FUNCTION ops.tvf_QueryStoreCompare (@BaselineLabel varchar(32), @CurrentLabel varchar(32), @Threshold decimal(5, 2))
RETURNS TABLE
AS
RETURN
    WITH b AS (SELECT * FROM ops.QueryStoreBaseline WHERE Label = @BaselineLabel AND TakenAt = (SELECT MAX(TakenAt) FROM ops.QueryStoreBaseline WHERE Label = @BaselineLabel)),
         c AS (SELECT * FROM ops.QueryStoreBaseline WHERE Label = @CurrentLabel  AND TakenAt = (SELECT MAX(TakenAt) FROM ops.QueryStoreBaseline WHERE Label = @CurrentLabel))
    SELECT c.ObjectName, LEFT(c.QueryText, 160) AS QueryText, c.QueryHash,
           b.AvgDurationMs AS BeforeMs, c.AvgDurationMs AS AfterMs, CAST(c.AvgDurationMs / NULLIF(b.AvgDurationMs, 0) AS decimal(8, 2)) AS DurationRatio,
           b.AvgReads AS BeforeReads, c.AvgReads AS AfterReads, CAST(c.AvgReads / NULLIF(b.AvgReads, 0) AS decimal(8, 2)) AS ReadsRatio,
           b.PlanCount AS BeforePlans, c.PlanCount AS AfterPlans, c.Executions
    FROM c JOIN b ON b.QueryHash = c.QueryHash
    WHERE c.Executions >= 10 AND b.AvgDurationMs >= 1
      AND (c.AvgDurationMs > b.AvgDurationMs * @Threshold OR c.AvgReads > b.AvgReads * @Threshold);
GO
GRANT EXECUTE ON ops.usp_QueryStoreBaseline TO waybill_ops;
GRANT SELECT ON ops.tvf_QueryStoreCompare TO waybill_ops;
GO

EXEC ops.usp_QueryStoreBaseline @Label = 'deploy';
SELECT TOP (10) ObjectName, LEFT(QueryText, 100) AS QueryText, Executions, AvgCpuMs, AvgDurationMs, AvgReads, PlanCount
FROM ops.QueryStoreBaseline WHERE Label = 'deploy' ORDER BY BaselineId DESC;
GO
