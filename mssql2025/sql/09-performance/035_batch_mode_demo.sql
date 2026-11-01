/* 09-performance/035_batch_mode_demo.sql
   Batch mode на columnstore и на rowstore, adaptive join, interleaved execution для multi-statement TVF.
   Читает режимы операторов из последнего фактического плана (LAST_QUERY_PLAN_STATS = ON). diagnostic: safe to re-run.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Помощник: режимы выполнения операторов последнего фактического плана запроса по метке в тексте
CREATE OR ALTER PROCEDURE ops.usp_ShowExecutionModes
    @Tag nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT TOP (40)
           op.value('@NodeId', 'int') AS node,
           op.value('@PhysicalOp', 'varchar(60)') AS physical_op,
           op.value('@LogicalOp', 'varchar(60)') AS logical_op,
           op.value('@EstimatedExecutionMode', 'varchar(10)') AS est_mode,
           op.value('(RunTimeInformation/RunTimeCountersPerThread/@ActualExecutionMode)[1]', 'varchar(10)') AS actual_mode,
           CAST(op.value('@EstimateRows', 'float') AS bigint) AS est_rows,
           op.value('(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)[1]', 'bigint') AS actual_rows,
           op.value('(AdaptiveJoin/@IsAdaptive)[1]', 'bit') AS is_adaptive,
           op.value('(RunTimeInformation/RunTimeCountersPerThread/@ActualJoinType)[1]', 'varchar(20)') AS actual_join_type
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    CROSS APPLY sys.dm_exec_query_plan_stats(qs.plan_handle) AS qps
    CROSS APPLY qps.query_plan.nodes('//RelOp') AS n (op)
    WHERE st.text LIKE N'%' + @Tag + N'%' AND st.text NOT LIKE N'%usp_ShowExecutionModes%'
    ORDER BY qs.last_execution_time DESC, node;
END;
GO

-- 1. Агрегат по событиям: NCCI → batch mode; тот же запрос с принудительным rowstore-индексом
SELECT /* bm: ncci */ CarrierId, StatusId, COUNT_BIG(*) AS events, MIN(OccurredAt) AS first_at, MAX(OccurredAt) AS last_at
FROM ship.TrackingEvent GROUP BY CarrierId, StatusId;
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: ncci';

SELECT /* bm: rowstore */ CarrierId, StatusId, COUNT_BIG(*) AS events, MIN(OccurredAt) AS first_at, MAX(OccurredAt) AS last_at
FROM ship.TrackingEvent WITH (INDEX (PK_TrackingEvent)) GROUP BY CarrierId, StatusId;
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: rowstore';   -- batch mode on rowstore возможен при достаточном объёме и compat 150+; иначе Row

-- 2. Adaptive join: порог строк решает hash или nested loops во время выполнения
SELECT /* bm: adaptive */ s.ShipmentId, e.StatusId, e.OccurredAt
FROM ship.Shipment AS s
JOIN ship.TrackingEvent AS e ON e.ShipmentId = s.ShipmentId
WHERE s.StatusId = 10;                                    -- редкий статус: мало строк со стороны Shipment
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: adaptive';   -- is_adaptive = 1, actual_join_type — NestedLoops

SELECT /* bm: adaptive-many */ s.ShipmentId, e.StatusId, e.OccurredAt
FROM ship.Shipment AS s
JOIN ship.TrackingEvent AS e ON e.ShipmentId = s.ShipmentId
WHERE s.StatusId = 7;                                     -- частый статус
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: adaptive-many';   -- при выборе адаптивного плана — HashMatch
GO

-- 3. Interleaved execution: multi-statement TVF без него оценивается фиксированным числом строк (100)
CREATE OR ALTER FUNCTION ship.tvf_ShipmentsByStatusMs (@StatusId tinyint)
RETURNS @t TABLE (ShipmentId bigint PRIMARY KEY, CarrierId smallint, CreatedAt datetime2(3))
AS
BEGIN
    INSERT INTO @t SELECT ShipmentId, CarrierId, CreatedAt FROM ship.Shipment WHERE StatusId = @StatusId;
    RETURN;
END;
GO

SELECT /* bm: interleaved */ f.ShipmentId, e.OccurredAt, e.StatusId
FROM ship.tvf_ShipmentsByStatusMs(7) AS f
JOIN ship.TrackingEvent AS e ON e.ShipmentId = f.ShipmentId
WHERE e.StatusId = 5;
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: interleaved';   -- est_rows у Table Valued Function ≈ actual_rows, а не 100

-- Сравнение с отключённым interleaved execution
SELECT /* bm: interleaved-off */ f.ShipmentId, e.OccurredAt, e.StatusId
FROM ship.tvf_ShipmentsByStatusMs(7) AS f
JOIN ship.TrackingEvent AS e ON e.ShipmentId = f.ShipmentId
WHERE e.StatusId = 5
OPTION (USE HINT ('DISABLE_INTERLEAVED_EXECUTION_TVF'));
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: interleaved-off';   -- est_rows = 100

-- Inline-версия той же функции для сравнения (глава 7): оценка через статистику, никакой «100»
SELECT /* bm: inline */ COUNT_BIG(*) FROM ship.tvf_OverdueShipments(NULL, '2026-09-01') AS o JOIN ship.TrackingEvent AS e ON e.ShipmentId = o.ShipmentId;
EXEC ops.usp_ShowExecutionModes @Tag = N'bm: inline';
GO
