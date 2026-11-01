-- diagnostic: safe to re-run
/*
  080_deploy_checks.sql — проверки хранимого кода после деплоя (урок 7.8):
  1) модули с несуществующими ссылками; 2) модули с неправильными SET-опциями; 3) процедуры без SET NOCOUNT ON;
  4) дрейф: модули, изменённые позже последней миграции; 5) объекты без расширенного свойства Description.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Несуществующие ссылки
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) AS module_name,
       ISNULL(d.referenced_schema_name + '.', '') + d.referenced_entity_name AS missing_reference
FROM sys.sql_expression_dependencies AS d
WHERE d.referenced_id IS NULL AND d.is_ambiguous = 0 AND d.referenced_server_name IS NULL AND d.referenced_database_name IS NULL
  AND d.referenced_class = 1
ORDER BY module_name;

-- 2. Модули с неправильными SET-опциями
SELECT OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS module_name, m.uses_ansi_nulls, m.uses_quoted_identifier
FROM sys.sql_modules AS m
WHERE m.uses_ansi_nulls = 0 OR m.uses_quoted_identifier = 0;

-- 3. Процедуры без SET NOCOUNT ON
SELECT OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS procedure_name
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE o.type = 'P' AND o.is_ms_shipped = 0 AND m.definition NOT LIKE '%SET NOCOUNT ON%';

-- 4. Дрейф: модули, изменённые позже последней миграции (в пределах 1 минуты — не дрейф, а сама миграция)
DECLARE @lastMigration datetime2(3) = (SELECT MAX(AppliedAt) FROM dbo.SchemaMigrations);
SELECT OBJECT_SCHEMA_NAME(o.object_id) + '.' + OBJECT_NAME(o.object_id) AS module_name, o.type_desc, o.modify_date, @lastMigration AS last_migration
FROM sys.objects AS o
WHERE o.type IN ('P', 'FN', 'IF', 'TF', 'V', 'TR') AND o.is_ms_shipped = 0
  AND o.modify_date > DATEADD(MINUTE, 1, @lastMigration);

-- 5. Объекты без Description
SELECT s.name + '.' + o.name AS object_name, o.type_desc
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.type IN ('P', 'FN', 'IF', 'TF', 'U') AND o.is_ms_shipped = 0
  AND s.name IN (N'ops', N'ship', N'crm', N'ref', N'analytics')
  AND NOT EXISTS (SELECT 1 FROM sys.extended_properties AS ep WHERE ep.major_id = o.object_id AND ep.minor_id = 0 AND ep.name = N'Description')
ORDER BY object_name;
GO
