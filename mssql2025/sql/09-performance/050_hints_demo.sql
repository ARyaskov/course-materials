/* 09-performance/050_hints_demo.sql
   Хинты: OPTION (...) в тексте, Query Store hints без правки кода, ABORT_QUERY_EXECUTION (2025) для блокировки запроса.
   Хинты Query Store снимаются в конце скрипта. diagnostic: safe to re-run.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Хинты в тексте запроса: каждый — ответ на конкретную проблему
SELECT /* hints-demo: maxdop */ CarrierId, COUNT_BIG(*) AS events
FROM ship.TrackingEvent GROUP BY CarrierId
OPTION (MAXDOP 1);                                             -- отчёт не должен занимать все ядра OLTP-сервера

SELECT /* hints-demo: recompile */ ShipmentId FROM ship.Shipment WHERE StatusId = 10
OPTION (RECOMPILE);                                            -- план под фактическое значение; для редких вызовов дешевле, чем sniffing

SELECT /* hints-demo: use hint */ s.ShipmentId FROM ship.Shipment AS s JOIN ship.TrackingEvent AS e ON e.ShipmentId = s.ShipmentId
WHERE s.MerchantId = 2 AND e.StatusId = 7
OPTION (USE HINT ('DISABLE_BATCH_MODE_ADAPTIVE_JOINS'));       -- точечное отключение одной IQP-функции вместо смены compat level

SELECT name FROM sys.dm_exec_valid_use_hints ORDER BY name;     -- полный список допустимых USE HINT
GO

-- 2. Query Store hint: тот же эффект без правки текста (кода приложения / ORM)
DECLARE @query_id bigint = (SELECT TOP (1) q.query_id
                            FROM sys.query_store_query AS q JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
                            WHERE qt.query_sql_text LIKE N'%sla-v2%' AND qt.query_sql_text NOT LIKE N'%query_store%'
                            ORDER BY q.last_execution_time DESC);
IF @query_id IS NULL
    PRINT 'sla-v2 ещё не в Query Store: выполните 030_sla_report_before_after.sql';
ELSE
BEGIN
    EXEC sys.sp_query_store_set_hints @query_id = @query_id, @query_hints = N'OPTION (MAXDOP 2, USE HINT(''QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_160''))';
    SELECT qh.query_id, qh.query_hint_text, qh.source_desc, qh.last_query_hint_failure_reason_desc FROM sys.query_store_query_hints AS qh WHERE qh.query_id = @query_id;

    EXEC analytics.usp_RefreshCarrierSla @PeriodStart = '2026-07-01';   -- выполняется с хинтом; в плане: QueryStoreStatementHintText

    EXEC sys.sp_query_store_clear_hints @query_id = @query_id;
    SELECT COUNT(*) AS hints_left FROM sys.query_store_query_hints WHERE query_id = @query_id;
END;
GO

-- 3. ABORT_QUERY_EXECUTION (2025): запрос с этим хинтом завершается ошибкой до выполнения.
--    Применение через Query Store hint — способ «выключить» вредный запрос приложения, не трогая приложение.
DECLARE @bad_query_id bigint;
-- Кандидат: демонстрационный запрос, который мы сами только что выполнили
SELECT /* hints-demo: to-abort */ TOP (1) ShipmentId FROM ship.Shipment ORDER BY ShipmentId;
SET @bad_query_id = (SELECT TOP (1) q.query_id
                     FROM sys.query_store_query AS q JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
                     WHERE qt.query_sql_text LIKE N'%hints-demo: to-abort%' AND qt.query_sql_text NOT LIKE N'%query_store%'
                     ORDER BY q.last_execution_time DESC);
IF @bad_query_id IS NOT NULL
BEGIN
    EXEC sys.sp_query_store_set_hints @query_id = @bad_query_id, @query_hints = N'OPTION (USE HINT(''ABORT_QUERY_EXECUTION''))';
    BEGIN TRY
        SELECT /* hints-demo: to-abort */ TOP (1) ShipmentId FROM ship.Shipment ORDER BY ShipmentId;
        PRINT 'выполнился: Query Store не сопоставил текст (хинт применяется к точному query_id)';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('запрос остановлен хинтом: ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
    END CATCH;
    EXEC sys.sp_query_store_clear_hints @query_id = @bad_query_id;
END;
GO

-- 4. Что осталось из хинтов и форсирований (должно быть пусто после демонстрации)
SELECT query_id, query_hint_text, source_desc FROM sys.query_store_query_hints;
SELECT query_id, plan_id, is_forced_plan FROM sys.query_store_plan WHERE is_forced_plan = 1;
GO
