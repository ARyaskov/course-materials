/* 09-performance/015_parameter_sniffing_demo.sql
   Parameter sniffing на перекошенном столбце ship.Shipment.StatusId (70 % DELIVERED, 0.2 % CANCELLED).
   Создаёт индекс IX_Shipment_Status_CreatedAt и процедуру ship.usp_ShipmentsByStatus в трёх вариантах;
   диагностическая часть выводит планы и варианты PSP из Query Store. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Узкий индекс: seek + key lookup выгоден для редкого статуса, невыгоден для частого — почва для sniffing
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Shipment_Status_CreatedAt' AND object_id = OBJECT_ID(N'ship.Shipment'))
    CREATE INDEX IX_Shipment_Status_CreatedAt ON ship.Shipment (StatusId, CreatedAt DESC);
GO

-- Вариант 1: «как есть» — план кэшируется по первому значению @StatusId
CREATE OR ALTER PROCEDURE ship.usp_ShipmentsByStatus
    @StatusId tinyint,
    @Top      int = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) s.ShipmentId, s.TrackingNumber, s.CarrierId, s.MerchantId, s.CreatedAt, s.PromisedAt, s.DeliveredAt, s.WeightGrams
    FROM ship.Shipment AS s
    WHERE s.StatusId = @StatusId
    ORDER BY s.CreatedAt DESC;
END;
GO

-- Вариант 2: RECOMPILE — план под каждое значение, цена — компиляция на каждый вызов
CREATE OR ALTER PROCEDURE ship.usp_ShipmentsByStatus_Recompile
    @StatusId tinyint,
    @Top      int = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) s.ShipmentId, s.TrackingNumber, s.CarrierId, s.MerchantId, s.CreatedAt, s.PromisedAt, s.DeliveredAt, s.WeightGrams
    FROM ship.Shipment AS s
    WHERE s.StatusId = @StatusId
    ORDER BY s.CreatedAt DESC
    OPTION (RECOMPILE);
END;
GO

-- Вариант 3: OPTIMIZE FOR — стабильный план «для типичного» значения; редкие значения живут с ним
CREATE OR ALTER PROCEDURE ship.usp_ShipmentsByStatus_OptimizeFor
    @StatusId tinyint,
    @Top      int = 1000
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) s.ShipmentId, s.TrackingNumber, s.CarrierId, s.MerchantId, s.CreatedAt, s.PromisedAt, s.DeliveredAt, s.WeightGrams
    FROM ship.Shipment AS s
    WHERE s.StatusId = @StatusId
    ORDER BY s.CreatedAt DESC
    OPTION (OPTIMIZE FOR (@StatusId = 7));
END;
GO

-- diagnostic: safe to re-run
-- Перекос по статусу
SELECT st.Code, COUNT(*) AS shipments, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5, 2)) AS pct
FROM ship.Shipment AS s JOIN ref.ShipmentStatus AS st ON st.StatusId = s.StatusId
GROUP BY st.Code ORDER BY shipments DESC;

-- Гистограмма статистики по индексу: что видит оптимизатор
SELECT s.name, sp.rows, sp.rows_sampled, sp.last_updated, sp.steps
FROM sys.stats AS s CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.object_id = OBJECT_ID(N'ship.Shipment') AND s.name = N'IX_Shipment_Status_CreatedAt';
SELECT range_high_key, equal_rows, range_rows, distinct_range_rows
FROM sys.dm_db_stats_histogram(OBJECT_ID(N'ship.Shipment'), (SELECT stats_id FROM sys.stats WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Status_CreatedAt'));

-- Прогрев в двух порядках: сначала редкое значение (10 = CANCELLED), потом частое (7 = DELIVERED)
DBCC FREEPROCCACHE WITH NO_INFOMSGS;
EXEC ship.usp_ShipmentsByStatus @StatusId = 10;   -- план: seek + key lookup
EXEC ship.usp_ShipmentsByStatus @StatusId = 7;    -- тот же план на 35 000 строк: тысячи lookup-ов
EXEC ship.usp_ShipmentsByStatus_Recompile @StatusId = 10;
EXEC ship.usp_ShipmentsByStatus_Recompile @StatusId = 7;
EXEC ship.usp_ShipmentsByStatus_OptimizeFor @StatusId = 10;
EXEC ship.usp_ShipmentsByStatus_OptimizeFor @StatusId = 7;

-- Планы из кэша: параметры компиляции и фактические чтения
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT OBJECT_NAME(ps.object_id) AS proc_name, ps.execution_count, ps.total_logical_reads, ps.last_logical_reads, ps.min_logical_reads, ps.max_logical_reads,
       qp.query_plan.value('(//ParameterList/ColumnReference[@Column="@StatusId"]/@ParameterCompiledValue)[1]', 'varchar(20)') AS compiled_for,
       qp.query_plan.exist('//RelOp[@PhysicalOp="Key Lookup"]') AS has_key_lookup
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id) LIKE N'usp_ShipmentsByStatus%';

-- PSP optimization: если оптимизатор счёл перекос достаточным, у запроса появится dispatcher и варианты планов
SELECT q.query_id, qv.query_variant_query_id, qv.parent_query_id, qv.dispatcher_plan_id, LEFT(qt.query_sql_text, 160) AS variant_text
FROM sys.query_store_query_variant AS qv
JOIN sys.query_store_query AS q ON q.query_id = qv.query_variant_query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text LIKE N'%usp_ShipmentsByStatus%' OR qt.query_sql_text LIKE N'%PLAN PER VALUE%';
GO
