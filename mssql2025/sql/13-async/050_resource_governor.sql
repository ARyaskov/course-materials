/* 13-async/050_resource_governor.sql
   Resource Governor: пул и группа для фоновой нагрузки (симулятор, отчёты, задания) с ограничением CPU и tempdb (2025),
   классификатор по APP_NAME(). Серверные настройки параллелизма. Идемпотентен.
*/
USE master;
GO
SET NOCOUNT ON;
GO

-- 1. Параллелизм экземпляра: порог стоимости 50 (OLTP-запросы остаются последовательными), MAXDOP по ядрам (не более 8)
EXEC sys.sp_configure N'show advanced options', 1; RECONFIGURE;
EXEC sys.sp_configure N'cost threshold for parallelism', 50; RECONFIGURE;
DECLARE @cores int = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @maxdop int = IIF(@cores > 8, 8, @cores);
EXEC sys.sp_configure N'max degree of parallelism', @maxdop; RECONFIGURE;
GO

-- 2. Пулы: фоновая нагрузка не более 30 % CPU при конкуренции, tempdb ограничен
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'waybill_background')
    CREATE RESOURCE POOL waybill_background WITH (MIN_CPU_PERCENT = 0, MAX_CPU_PERCENT = 30, CAP_CPU_PERCENT = 50, MAX_MEMORY_PERCENT = 40);
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'waybill_api')
    CREATE RESOURCE POOL waybill_api WITH (MIN_CPU_PERCENT = 30, MAX_CPU_PERCENT = 100);
GO

-- 3. Группы: запросы фоновой нагрузки — MAXDOP 2, память на запрос до 20 %, tempdb до 4 ГБ на группу (2025: GROUP_MAX_TEMPDB_DATA_MB)
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'waybill_background_wg')
    CREATE WORKLOAD GROUP waybill_background_wg
        WITH (IMPORTANCE = LOW, MAX_DOP = 2, REQUEST_MAX_MEMORY_GRANT_PERCENT = 20, REQUEST_MAX_CPU_TIME_SEC = 600, GROUP_MAX_REQUESTS = 16)
        USING waybill_background;
IF NOT EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'waybill_api_wg')
    CREATE WORKLOAD GROUP waybill_api_wg WITH (IMPORTANCE = HIGH, REQUEST_MAX_MEMORY_GRANT_PERCENT = 10) USING waybill_api;
GO
BEGIN TRY
    EXEC sys.sp_executesql N'ALTER WORKLOAD GROUP waybill_background_wg WITH (GROUP_MAX_TEMPDB_DATA_MB = 4096);';   -- 2025: превышение → ошибка 1138 у запроса
END TRY
BEGIN CATCH
    PRINT CONCAT('tempdb governance недоступна: ', ERROR_MESSAGE());
END CATCH;
GO

-- 4. Классификатор: по имени приложения; всё остальное — default
-- Функцию, назначенную классификатором, изменить нельзя (ошибка 10924): на время пересоздания отвязываем её от RG
IF EXISTS (SELECT 1 FROM sys.resource_governor_configuration WHERE classifier_function_id = OBJECT_ID(N'dbo.fn_WaybillClassifier'))
BEGIN
    ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);
    ALTER RESOURCE GOVERNOR RECONFIGURE;
END
GO
CREATE OR ALTER FUNCTION dbo.fn_WaybillClassifier ()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @app sysname = APP_NAME();
    RETURN CASE
        WHEN @app LIKE N'Waybill.Api%' THEN N'waybill_api_wg'
        WHEN @app IN (N'Waybill.Simulator', N'Waybill.Migrator') OR @app LIKE N'SQLAgent%' THEN N'waybill_background_wg'
        ELSE N'default'
    END;
END;
GO
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.fn_WaybillClassifier);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO

-- diagnostic: safe to re-run
SELECT is_enabled, classifier_function_id, OBJECT_NAME(classifier_function_id) AS classifier FROM sys.resource_governor_configuration;
SELECT p.name AS pool, p.min_cpu_percent, p.max_cpu_percent, p.cap_cpu_percent, p.max_memory_percent, g.name AS wg, g.importance, g.max_dop, g.request_max_memory_grant_percent
FROM sys.resource_governor_resource_pools AS p JOIN sys.resource_governor_workload_groups AS g ON g.pool_id = p.pool_id ORDER BY p.name;
-- Кто в какой группе сейчас
SELECT s.session_id, s.program_name, g.name AS workload_group FROM sys.dm_exec_sessions AS s JOIN sys.dm_resource_governor_workload_groups AS g ON g.group_id = s.group_id
WHERE s.is_user_process = 1;
-- Статистика групп: запросы, CPU, ожидания grant
SELECT name, total_request_count, total_cpu_usage_ms, total_queued_request_count, total_reduced_memgrant_count FROM sys.dm_resource_governor_workload_groups;
SELECT name, value_in_use FROM sys.configurations WHERE name IN (N'cost threshold for parallelism', N'max degree of parallelism');
GO
