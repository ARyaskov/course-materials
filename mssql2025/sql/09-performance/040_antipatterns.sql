/* 09-performance/040_antipatterns.sql
   Поиск анти-паттернов в кэше планов и в коде: неявные преобразования, non-SARGable предикаты, скалярные UDF,
   missing index warnings; переписанные варианты на данных Waybill. diagnostic: safe to re-run.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Неявные преобразования в кэше планов (PlanAffectingConvert, ConvertIssue = Seek Plan / Cardinality Estimate)
;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT TOP (30)
       cp.usecounts, cp.objtype,
       w.value('@ConvertIssue', 'varchar(40)')  AS convert_issue,
       w.value('@Expression', 'nvarchar(400)')  AS expression,
       LEFT(st.text, 300) AS sql_text,
       qp.query_plan
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY qp.query_plan.nodes('//Warnings/PlanAffectingConvert') AS n (w)
WHERE qp.dbid = DB_ID()
ORDER BY cp.usecounts DESC;

-- 2. Планы с предупреждениями: spill в tempdb, missing index, no join predicate
;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT TOP (30)
       cp.usecounts,
       qp.query_plan.exist('//MissingIndex')        AS missing_index,
       qp.query_plan.exist('//SpillToTempDb')       AS spill,
       qp.query_plan.exist('//Warnings/NoJoinPredicate') AS no_join_predicate,
       qp.query_plan.value('(//MissingIndex/@Impact)[1]', 'float') AS missing_index_impact,
       LEFT(st.text, 300) AS sql_text
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE qp.dbid = DB_ID()
  AND (qp.query_plan.exist('//MissingIndex') = 1 OR qp.query_plan.exist('//SpillToTempDb') = 1 OR qp.query_plan.exist('//Warnings/NoJoinPredicate') = 1)
ORDER BY cp.usecounts DESC;

-- 3. Скалярные UDF, которые не встраиваются (INLINE = OFF или не удовлетворяют условиям)
SELECT SCHEMA_NAME(o.schema_id) + '.' + o.name AS function_name, m.is_inlineable, m.inline_type
FROM sys.sql_modules AS m JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE o.type = 'FN' AND (m.is_inlineable = 0 OR m.inline_type = 0);

-- 4. Модули, которые вызывают скалярные UDF в предикатах (грубая эвристика по тексту)
SELECT SCHEMA_NAME(o.schema_id) + '.' + o.name AS module_name, o.type_desc
FROM sys.sql_modules AS m JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE m.definition LIKE N'%WHERE%fn[_]%(%' AND o.type IN ('P', 'V', 'IF', 'TF');

-- 5. Missing index DMV: что просил оптимизатор (не создавать вслепую — сверять с существующими индексами)
SELECT TOP (20)
       CAST(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans) AS decimal(18, 0)) AS score,
       mid.statement AS table_name, mid.equality_columns, mid.inequality_columns, mid.included_columns,
       migs.user_seeks, migs.user_scans, migs.avg_user_impact, migs.last_user_seek
FROM sys.dm_db_missing_index_groups AS mig
JOIN sys.dm_db_missing_index_group_stats AS migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details AS mid ON mid.index_handle = mig.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY score DESC;
GO

-- 6. Переписывание на данных Waybill: до/после (STATISTICS IO показывает разницу)
SET STATISTICS IO ON;

-- 6a. Функция на столбце → диапазон
SELECT COUNT(*) FROM ship.Shipment WHERE YEAR(CreatedAt) = 2026 AND MONTH(CreatedAt) = 7;                                   -- scan
SELECT COUNT(*) FROM ship.Shipment WHERE CreatedAt >= '2026-07-01' AND CreatedAt < '2026-08-01';                             -- seek по IX_Shipment_CreatedAt_Report

-- 6b. Неявное преобразование: varchar-столбец против nvarchar-параметра
DECLARE @trackingN nvarchar(64) = N'FX0000100001', @trackingV varchar(64) = 'FX0000100001';
SELECT ShipmentId FROM ship.Shipment WHERE TrackingNumberNormalized = @trackingN;   -- CONVERT_IMPLICIT на столбце → scan или seek с предупреждением
SELECT ShipmentId FROM ship.Shipment WHERE TrackingNumberNormalized = @trackingV;   -- seek

-- 6c. OR по разным столбцам → UNION ALL (или два индекса + concatenation, если оптимизатор выберет сам)
SELECT ShipmentId FROM ship.Shipment WHERE TrackingNumberNormalized = 'FX0000100001' OR ExternalOrderId = N'SEED-000002';
SELECT ShipmentId FROM ship.Shipment WHERE TrackingNumberNormalized = 'FX0000100001'
UNION
SELECT ShipmentId FROM ship.Shipment WHERE ExternalOrderId = N'SEED-000002';

-- 6d. Скалярная UDF на строку → соединение с агрегатом
SELECT TOP (1000) s.ShipmentId, analytics.fn_DeliveryHours_v1(s.ShipmentId) AS Hours FROM ship.Shipment AS s WHERE s.StatusId = 7 ORDER BY s.ShipmentId;
SELECT TOP (1000) s.ShipmentId, CAST(DATEDIFF(MINUTE, s.CreatedAt, d.DeliveredAt) / 60.0 AS decimal(8, 1)) AS Hours
FROM ship.Shipment AS s
JOIN (SELECT ShipmentId, MIN(OccurredAt) AS DeliveredAt FROM ship.TrackingEvent WHERE StatusId = 7 GROUP BY ShipmentId) AS d ON d.ShipmentId = s.ShipmentId
WHERE s.StatusId = 7 ORDER BY s.ShipmentId;

-- 6e. LIKE с ведущим % → полнотекст/нормализованный ключ; здесь — сравнение стоимости
SELECT COUNT(*) FROM ship.Address WHERE Street LIKE N'%Linden%';                     -- scan всегда
SELECT COUNT(*) FROM ship.Address WHERE Street LIKE N'Linden%';                      -- seek при индексе по Street

-- 6f. Пагинация OFFSET на глубокой странице → keyset
SELECT ShipmentId, CreatedAt FROM ship.Shipment WHERE MerchantId = 1 ORDER BY CreatedAt DESC, ShipmentId DESC OFFSET 15000 ROWS FETCH NEXT 50 ROWS ONLY;
DECLARE @lastCreated datetime2(3) = '2026-04-01T00:00:00', @lastId bigint = 0;
SELECT TOP (50) ShipmentId, CreatedAt FROM ship.Shipment
WHERE MerchantId = 1 AND (CreatedAt < @lastCreated OR (CreatedAt = @lastCreated AND ShipmentId < @lastId))
ORDER BY CreatedAt DESC, ShipmentId DESC;

SET STATISTICS IO OFF;
GO
