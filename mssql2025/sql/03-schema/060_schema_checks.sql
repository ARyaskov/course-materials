-- diagnostic: safe to re-run
/*
  060_schema_checks.sql — проверки схемы (уроки 3.3–3.5):
  1) внешние ключи без индекса по своим столбцам;
  2) недоверенные и отключённые ограничения;
  3) ограничения с системными именами;
  4) подозрительные типы столбцов;
  5) все ограничения ship.Shipment одним списком.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. FK без индекса
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS child_table,
       fk.name AS fk_name,
       STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS fk_columns,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS parent_table
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
WHERE NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    WHERE i.object_id = fk.parent_object_id
      AND NOT EXISTS
      (
          SELECT fkc2.constraint_column_id, fkc2.parent_column_id
          FROM sys.foreign_key_columns AS fkc2 WHERE fkc2.constraint_object_id = fk.object_id
          EXCEPT
          SELECT ic.key_ordinal, ic.column_id
          FROM sys.index_columns AS ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.key_ordinal > 0
      )
)
GROUP BY fk.parent_object_id, fk.name, fk.referenced_object_id
ORDER BY child_table, fk_name;

-- 2. Недоверенные / отключённые ограничения
SELECT 'FK' AS kind, OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) AS table_name, name, is_not_trusted, is_disabled
FROM sys.foreign_keys WHERE is_not_trusted = 1 OR is_disabled = 1
UNION ALL
SELECT 'CHECK', OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id), name, is_not_trusted, is_disabled
FROM sys.check_constraints WHERE is_not_trusted = 1 OR is_disabled = 1;

-- 3. Системные имена ограничений
SELECT 'DEFAULT' AS kind, OBJECT_NAME(parent_object_id) AS table_name, name FROM sys.default_constraints WHERE is_system_named = 1
UNION ALL SELECT 'CHECK', OBJECT_NAME(parent_object_id), name FROM sys.check_constraints WHERE is_system_named = 1
UNION ALL SELECT 'KEY', OBJECT_NAME(parent_object_id), name FROM sys.key_constraints WHERE is_system_named = 1
UNION ALL SELECT 'FK', OBJECT_NAME(parent_object_id), name FROM sys.foreign_keys WHERE is_system_named = 1;

-- 4. Подозрительные типы
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS table_name, c.name AS column_name, t.name AS type_name,
       CASE t.name
           WHEN 'datetime' THEN N'заменить на datetime2(3)'
           WHEN 'text' THEN N'заменить на nvarchar(max)/varchar(max)'
           WHEN 'ntext' THEN N'заменить на nvarchar(max)'
           WHEN 'image' THEN N'заменить на varbinary(max)'
           WHEN 'money' THEN N'проверить расчёты, рассмотреть decimal(19,4)'
           WHEN 'float' THEN N'проверить, не деньги ли'
           WHEN 'nvarchar' THEN IIF(c.max_length = -1, N'(max): проверить необходимость', N'')
           WHEN 'varchar' THEN IIF(c.max_length = -1, N'(max): проверить необходимость', N'')
       END AS recommendation
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
JOIN sys.tables AS tb ON tb.object_id = c.object_id
WHERE tb.is_ms_shipped = 0 AND OBJECT_SCHEMA_NAME(c.object_id) <> N'demo'
  AND (t.name IN ('datetime', 'text', 'ntext', 'image', 'money', 'smallmoney', 'float', 'real', 'smalldatetime')
       OR (t.name IN ('nvarchar', 'varchar', 'varbinary') AND c.max_length = -1))
ORDER BY table_name, c.column_id;

-- 5. Все ограничения ship.Shipment
SELECT 'PK/UQ' AS kind, kc.name, kc.type_desc COLLATE DATABASE_DEFAULT AS detail, NULL AS is_not_trusted FROM sys.key_constraints AS kc   -- COLLATE: у каталога своя коллация WHERE kc.parent_object_id = OBJECT_ID(N'ship.Shipment')
UNION ALL
SELECT 'FK', fk.name, OBJECT_NAME(fk.referenced_object_id), fk.is_not_trusted FROM sys.foreign_keys AS fk WHERE fk.parent_object_id = OBJECT_ID(N'ship.Shipment')
UNION ALL
SELECT 'CHECK', cc.name, cc.definition, cc.is_not_trusted FROM sys.check_constraints AS cc WHERE cc.parent_object_id = OBJECT_ID(N'ship.Shipment')
UNION ALL
SELECT 'DEFAULT', dc.name, dc.definition, NULL FROM sys.default_constraints AS dc WHERE dc.parent_object_id = OBJECT_ID(N'ship.Shipment')
ORDER BY kind, name;
GO
