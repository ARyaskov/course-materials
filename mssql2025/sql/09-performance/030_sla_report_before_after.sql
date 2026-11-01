/* 09-performance/030_sla_report_before_after.sql
   SLA-отчёт по перевозчикам: медленная версия (v1: non-SARGable предикат, скалярная UDF на строку, PERCENTILE_CONT)
   и рабочая версия (v2: диапазон по индексу, агрегат по NCCI в batch mode, APPROX_PERCENTILE_CONT).
   analytics.usp_RefreshCarrierSla — рабочая; analytics.usp_CarrierSlaReport — чтение витрины. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ---------- «До»: как это часто пишут ----------
-- Скалярная функция с доступом к данным; INLINE = OFF воспроизводит поведение до scalar UDF inlining (или функции, которую нельзя встроить)
CREATE OR ALTER FUNCTION analytics.fn_DeliveryHours_v1 (@ShipmentId bigint)
RETURNS decimal(8, 1)
WITH INLINE = OFF
AS
BEGIN
    DECLARE @created datetime2(3) = (SELECT CreatedAt FROM ship.Shipment WHERE ShipmentId = @ShipmentId);
    DECLARE @delivered datetime2(3) = (SELECT MIN(OccurredAt) FROM ship.TrackingEvent WHERE ShipmentId = @ShipmentId AND StatusId = 7);
    RETURN CAST(DATEDIFF(MINUTE, @created, @delivered) / 60.0 AS decimal(8, 1));
END;
GO

CREATE OR ALTER PROCEDURE analytics.usp_RefreshCarrierSla_v1
    @PeriodStart date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @month varchar(7) = CONVERT(varchar(7), @PeriodStart, 120);

    ;WITH per_shipment AS
    (
        SELECT /* sla-v1 */ s.ShipmentId, s.CarrierId, a.RegionId,
               analytics.fn_DeliveryHours_v1(s.ShipmentId) AS Hours,                       -- UDF на каждую строку
               IIF(s.StatusId = 7, 1, 0) AS IsDelivered,
               IIF(s.StatusId = 7 AND s.DeliveredAt > s.PromisedAt, 1, 0) AS IsLate
        FROM ship.Shipment AS s
        JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
        WHERE CONVERT(varchar(7), s.CreatedAt, 120) = @month                                -- функция на столбце: индекс по CreatedAt бесполезен
    ),
    with_pct AS
    (
        SELECT CarrierId, RegionId, IsDelivered, IsLate,
               PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY Hours) OVER (PARTITION BY CarrierId, RegionId) AS MedianHours,
               PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Hours) OVER (PARTITION BY CarrierId, RegionId) AS P95Hours
        FROM per_shipment
    )
    MERGE analytics.CarrierSla AS t
    USING (SELECT CarrierId, RegionId, COUNT(*) AS Shipments, SUM(IsDelivered) AS Delivered, SUM(IsLate) AS Late,
                  MAX(MedianHours) AS MedianHours, MAX(P95Hours) AS P95Hours
           FROM with_pct GROUP BY CarrierId, RegionId) AS src
       ON t.CarrierId = src.CarrierId AND t.PeriodStart = @PeriodStart AND ISNULL(t.RegionId, -1) = ISNULL(src.RegionId, -1)
    WHEN MATCHED THEN UPDATE SET Shipments = src.Shipments, Delivered = src.Delivered, Late = src.Late,
                                 MedianHours = src.MedianHours, P95Hours = src.P95Hours, RefreshedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (CarrierId, RegionId, PeriodStart, Shipments, Delivered, Late, MedianHours, P95Hours)
                          VALUES (src.CarrierId, src.RegionId, @PeriodStart, src.Shipments, src.Delivered, src.Late, src.MedianHours, src.P95Hours);
END;
GO

-- ---------- «После» ----------
-- Индекс под диапазон по дате создания с покрытием столбцов отчёта
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_CreatedAt_Report' AND object_id = OBJECT_ID(N'ship.Shipment'))
    CREATE INDEX IX_Shipment_CreatedAt_Report ON ship.Shipment (CreatedAt)
        INCLUDE (CarrierId, DestinationAddressId, StatusId, PromisedAt, DeliveredAt);
GO

CREATE OR ALTER PROCEDURE analytics.usp_RefreshCarrierSla
    @PeriodStart date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @from datetime2(3) = @PeriodStart, @to datetime2(3) = DATEADD(MONTH, 1, @PeriodStart);

    ;WITH delivered AS
    (
        SELECT /* sla-v2 */ e.ShipmentId, MIN(e.OccurredAt) AS DeliveredAt            -- один проход по NCCI в batch mode
        FROM ship.TrackingEvent AS e
        WHERE e.StatusId = 7 AND e.OccurredAt >= @from AND e.OccurredAt < DATEADD(DAY, 60, @to)
        GROUP BY e.ShipmentId
    ),
    per_shipment AS
    (
        SELECT s.CarrierId, a.RegionId,
               CAST(DATEDIFF(MINUTE, s.CreatedAt, d.DeliveredAt) / 60.0 AS decimal(8, 1)) AS Hours,
               IIF(d.ShipmentId IS NOT NULL, 1, 0) AS IsDelivered,
               IIF(d.DeliveredAt > s.PromisedAt, 1, 0) AS IsLate
        FROM ship.Shipment AS s
        JOIN ship.Address AS a ON a.AddressId = s.DestinationAddressId
        LEFT JOIN delivered AS d ON d.ShipmentId = s.ShipmentId
        WHERE s.CreatedAt >= @from AND s.CreatedAt < @to                                   -- SARGable диапазон
    ),
    agg AS
    (
        SELECT CarrierId, RegionId, COUNT(*) AS Shipments, SUM(IsDelivered) AS Delivered, SUM(IsLate) AS Late,
               CAST(APPROX_PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY Hours) AS decimal(8, 1)) AS MedianHours,
               CAST(APPROX_PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Hours) AS decimal(8, 1)) AS P95Hours
        FROM per_shipment
        GROUP BY CarrierId, RegionId
    )
    MERGE analytics.CarrierSla AS t
    USING agg AS src
       ON t.CarrierId = src.CarrierId AND t.PeriodStart = @PeriodStart AND ISNULL(t.RegionId, -1) = ISNULL(src.RegionId, -1)
    WHEN MATCHED THEN UPDATE SET Shipments = src.Shipments, Delivered = src.Delivered, Late = src.Late,
                                 MedianHours = src.MedianHours, P95Hours = src.P95Hours, RefreshedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (CarrierId, RegionId, PeriodStart, Shipments, Delivered, Late, MedianHours, P95Hours)
                          VALUES (src.CarrierId, src.RegionId, @PeriodStart, src.Shipments, src.Delivered, src.Late, src.MedianHours, src.P95Hours);
END;
GO

-- Чтение витрины: необязательные фильтры в стиле «@p IS NULL OR col = @p» (Optional Parameter Plan Optimization)
CREATE OR ALTER PROCEDURE analytics.usp_CarrierSlaReport
    @From        date,
    @To          date,
    @CarrierCode varchar(16) = NULL,
    @RegionCode  varchar(16) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.Code AS Carrier, r.Code AS Region, cs.PeriodStart,
           cs.Shipments, cs.Delivered, cs.Late,
           CAST(100.0 * cs.Late / NULLIF(cs.Delivered, 0) AS decimal(5, 1)) AS LatePct,
           cs.MedianHours, cs.P95Hours, cs.RefreshedAt
    FROM analytics.CarrierSla AS cs
    JOIN ref.Carrier AS c ON c.CarrierId = cs.CarrierId
    LEFT JOIN ref.Region AS r ON r.RegionId = cs.RegionId
    WHERE cs.PeriodStart >= @From AND cs.PeriodStart < @To
      AND (@CarrierCode IS NULL OR c.Code = @CarrierCode)
      AND (@RegionCode  IS NULL OR r.Code = @RegionCode)
    ORDER BY cs.PeriodStart, c.Code, r.Code;
END;
GO

-- diagnostic: safe to re-run
SET STATISTICS IO, TIME ON;
PRINT '--- v1 ---';
EXEC analytics.usp_RefreshCarrierSla_v1 @PeriodStart = '2026-07-01';
PRINT '--- v2 ---';
EXEC analytics.usp_RefreshCarrierSla @PeriodStart = '2026-07-01';
SET STATISTICS IO, TIME OFF;

EXEC analytics.usp_CarrierSlaReport @From = '2026-07-01', @To = '2026-08-01';
EXEC analytics.usp_CarrierSlaReport @From = '2026-07-01', @To = '2026-08-01', @CarrierCode = 'NORDPOST';

-- Сравнение в Query Store по меткам в тексте запроса
SELECT CASE WHEN qt.query_sql_text LIKE N'%sla-v1%' THEN 'v1' ELSE 'v2' END AS version,
       q.query_id, p.plan_id,
       SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_duration * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(18, 1)) AS avg_duration_ms,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) / 1000.0 AS decimal(18, 1)) AS avg_cpu_ms,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS decimal(18, 0)) AS avg_reads,
       CAST(SUM(rs.avg_query_max_used_memory * rs.count_executions) / NULLIF(SUM(rs.count_executions), 0) AS decimal(18, 0)) AS avg_memory_pages
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE qt.query_sql_text LIKE N'%sla-v1%' OR qt.query_sql_text LIKE N'%sla-v2%'
GROUP BY qt.query_sql_text, q.query_id, p.plan_id
ORDER BY version, q.query_id;

-- Режим выполнения операторов последнего фактического плана v2 (LAST_QUERY_PLAN_STATS = ON)
;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT op.value('@PhysicalOp', 'varchar(60)') AS physical_op,
       op.value('@EstimatedExecutionMode', 'varchar(10)') AS est_mode,
       op.value('(RunTimeInformation/RunTimeCountersPerThread/@ActualExecutionMode)[1]', 'varchar(10)') AS actual_mode,
       op.value('@EstimateRows', 'float') AS est_rows,
       op.value('(RunTimeInformation/RunTimeCountersPerThread/@ActualRows)[1]', 'float') AS actual_rows
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan_stats(ps.plan_handle) AS qps
CROSS APPLY qps.query_plan.nodes('//RelOp') AS n (op)
WHERE ps.object_id = OBJECT_ID(N'analytics.usp_RefreshCarrierSla');
GO
