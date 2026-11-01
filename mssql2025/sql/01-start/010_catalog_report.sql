-- diagnostic: safe to re-run
/*
  010_catalog_report.sql — отчёт по каталогу базы Waybill (урок 1.6 / 1.8).
  Четыре результата: объекты по схемам, таблицы с размером, индексы схемы ship, внешние ключи.
  Работает на пустой базе (после 002_schemas.sql).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Объекты по схемам
SELECT s.name AS schema_name,
       COUNT(CASE WHEN o.type = 'U'  THEN 1 END) AS tables,
       COUNT(CASE WHEN o.type = 'V'  THEN 1 END) AS views,
       COUNT(CASE WHEN o.type = 'P'  THEN 1 END) AS procedures,
       COUNT(CASE WHEN o.type IN ('FN', 'IF', 'TF') THEN 1 END) AS functions,
       COUNT(CASE WHEN o.type = 'SO' THEN 1 END) AS sequences,
       (SELECT COUNT(*) FROM sys.table_types AS tt WHERE tt.schema_id = s.schema_id) AS table_types
FROM sys.schemas AS s
LEFT JOIN sys.objects AS o ON o.schema_id = s.schema_id AND o.is_ms_shipped = 0
WHERE s.name IN (N'dbo', N'ref', N'crm', N'ship', N'ops', N'bill', N'analytics')
GROUP BY s.name, s.schema_id
ORDER BY s.name;

-- 2. Таблицы: строки, размер, сжатие, temporal/ledger
SELECT s.name AS schema_name, t.name AS table_name,
       SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS [rows],
       CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS decimal(10, 2)) AS used_mb,
       MAX(p.data_compression_desc) AS compression,
       t.temporal_type_desc, t.ledger_type_desc, t.is_memory_optimized, t.lock_escalation_desc
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.partitions AS p ON p.object_id = t.object_id
JOIN sys.dm_db_partition_stats AS ps ON ps.partition_id = p.partition_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name, t.temporal_type_desc, t.ledger_type_desc, t.is_memory_optimized, t.lock_escalation_desc
ORDER BY s.name, t.name;

-- 3. Индексы схемы ship: ключевые и включённые столбцы
SELECT OBJECT_NAME(i.object_id) AS table_name, i.name AS index_name, i.type_desc, i.is_unique, i.is_primary_key, i.filter_definition,
       STRING_AGG(IIF(ic.key_ordinal > 0, c.name + IIF(ic.is_descending_key = 1, ' DESC', ''), NULL), ', ')
           WITHIN GROUP (ORDER BY ic.key_ordinal) AS key_columns,
       STRING_AGG(IIF(ic.is_included_column = 1, c.name, NULL), ', ') AS included_columns
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE OBJECT_SCHEMA_NAME(i.object_id) = N'ship'
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, i.is_unique, i.is_primary_key, i.filter_definition
ORDER BY table_name, i.index_id;

-- 4. Внешние ключи с флагами доверия
SELECT fk.name,
       OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS referencing_table,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS referenced_table,
       fk.delete_referential_action_desc, fk.update_referential_action_desc, fk.is_not_trusted, fk.is_disabled
FROM sys.foreign_keys AS fk
ORDER BY referencing_table, fk.name;
GO
