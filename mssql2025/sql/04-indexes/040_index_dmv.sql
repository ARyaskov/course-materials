-- diagnostic: safe to re-run
/*
  040_index_dmv.sql — ревизия индексов (урок 4.8): пропущенные, использование, операционная статистика,
  перекрытия по префиксу ключа, «широкие» таблицы.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Пропущенные индексы по оценке оптимизатора
SELECT TOP (20)
    mid.statement AS table_name, mid.equality_columns, mid.inequality_columns, mid.included_columns,
    migs.user_seeks, migs.user_scans, migs.avg_total_user_cost, migs.avg_user_impact,
    migs.avg_total_user_cost * migs.avg_user_impact / 100.0 * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    migs.last_user_seek
FROM sys.dm_db_missing_index_details AS mid
JOIN sys.dm_db_missing_index_groups AS mig ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats AS migs ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;

-- 2. Использование индексов и размер
SELECT OBJECT_SCHEMA_NAME(i.object_id) + '.' + OBJECT_NAME(i.object_id) AS table_name, i.name, i.type_desc, i.is_unique, i.filter_definition,
       ISNULL(us.user_seeks, 0) AS seeks, ISNULL(us.user_scans, 0) AS scans, ISNULL(us.user_lookups, 0) AS lookups, ISNULL(us.user_updates, 0) AS updates,
       us.last_user_seek, us.last_user_scan, ps.used_page_count * 8 / 1024 AS size_mb
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us ON us.object_id = i.object_id AND us.index_id = i.index_id AND us.database_id = DB_ID()
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.type IN (1, 2, 5, 6)
ORDER BY table_name, i.index_id;

-- 3. Операционная статистика: блокировки и latch-и по индексам
SELECT OBJECT_NAME(ios.object_id) AS table_name, i.name,
       ios.range_scan_count, ios.singleton_lookup_count, ios.leaf_insert_count, ios.leaf_update_count, ios.leaf_delete_count,
       ios.row_lock_wait_count, ios.row_lock_wait_in_ms, ios.page_latch_wait_count, ios.page_io_latch_wait_in_ms
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios
JOIN sys.indexes AS i ON i.object_id = ios.object_id AND i.index_id = ios.index_id
WHERE OBJECT_SCHEMA_NAME(ios.object_id) IN (N'ship', N'ops', N'crm', N'ref')
ORDER BY ios.row_lock_wait_in_ms DESC, ios.range_scan_count DESC;

-- 4. Перекрытия: ключ одного индекса — префикс ключа другого
WITH idx AS
(
    SELECT i.object_id, i.name, i.index_id,
           STRING_AGG(IIF(ic.key_ordinal > 0, CAST(ic.column_id AS varchar(10)) + IIF(ic.is_descending_key = 1, 'D', 'A'), NULL), ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS key_sig
    FROM sys.indexes AS i
    JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.type = 2 AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    GROUP BY i.object_id, i.name, i.index_id
)
SELECT OBJECT_NAME(a.object_id) AS table_name, a.name AS narrower_index, b.name AS wider_index, a.key_sig AS narrower_key, b.key_sig AS wider_key
FROM idx AS a
JOIN idx AS b ON b.object_id = a.object_id AND b.index_id <> a.index_id
WHERE b.key_sig LIKE a.key_sig + ',%' OR b.key_sig = a.key_sig;

-- 5. Таблицы с большим числом индексов или индексами больше данных
SELECT OBJECT_NAME(i.object_id) AS table_name, COUNT(*) AS index_count,
       SUM(ps.used_page_count) * 8 / 1024 AS total_index_mb,
       MAX(IIF(i.index_id = 1, ps.used_page_count, 0)) * 8 / 1024 AS table_mb
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.type IN (1, 2)
GROUP BY i.object_id
HAVING COUNT(*) > 5 OR SUM(ps.used_page_count) > 2 * MAX(IIF(i.index_id = 1, ps.used_page_count, 0))
ORDER BY total_index_mb DESC;
GO
