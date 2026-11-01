/*
  040_drift_check.sql — контроль дрейфа схемы и настроек безопасности (глава 16).

  ops.usp_SchemaSnapshot @Label — снимок «отпечатков» по компонентам в ops.SchemaSnapshot:
    tables/columns, indexes, modules (хэш определений), constraints, permissions (роли waybill_*), masks, rls, settings (ops.Setting без ai.*.url)
  ops.usp_DriftCheck @BaselineLabel = 'deploy' — сравнивает текущее состояние с последним снимком с этой меткой:
    печатает изменённые компоненты и различия на уровне объектов (json_diff по имени).
  Деплой (apply.ps1 / CI) заканчивается EXEC ops.usp_SchemaSnapshot 'deploy'; задание Health report вызывает usp_DriftCheck.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.SchemaSnapshot', N'U') IS NULL
CREATE TABLE ops.SchemaSnapshot
(
    SnapshotId  int IDENTITY CONSTRAINT PK_SchemaSnapshot PRIMARY KEY,
    TakenAt     datetime2(0) NOT NULL CONSTRAINT DF_SchemaSnapshot_TakenAt DEFAULT SYSUTCDATETIME(),
    Label       varchar(32)  NOT NULL,
    Component   varchar(32)  NOT NULL,
    Hash        binary(32)   NOT NULL,
    Detail      json         NOT NULL,      -- [{"name":"ship.Shipment","hash":"…"}, …]
    CONSTRAINT UQ_SchemaSnapshot UNIQUE (Label, TakenAt, Component)
);
GO

-- Отпечатки по компонентам: имя объекта → хэш его определения
CREATE OR ALTER FUNCTION ops.tvf_SchemaFingerprints ()
RETURNS TABLE
AS
RETURN
    -- Таблицы: столбцы с типами, NULL, вычисляемые выражения
    SELECT 'tables' AS Component, (s.name + '.' + t.name) COLLATE DATABASE_DEFAULT AS Name,
           HASHBYTES('SHA2_256', (SELECT c.name, TYPE_NAME(c.user_type_id) AS t, c.max_length, c.precision, c.scale, c.is_nullable, c.is_identity, c.is_computed, cc.definition
                                  FROM sys.columns AS c LEFT JOIN sys.computed_columns AS cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
                                  WHERE c.object_id = t.object_id ORDER BY c.column_id FOR JSON PATH)) AS Hash
    FROM sys.tables AS t JOIN sys.schemas AS s ON s.schema_id = t.schema_id
    WHERE s.name NOT IN ('demo', 'dbo') AND t.temporal_type <> 1
    UNION ALL
    -- Индексы: ключи, включённые столбцы, фильтр, тип
    SELECT 'indexes', (s.name + '.' + t.name + '.' + i.name) COLLATE DATABASE_DEFAULT,
           HASHBYTES('SHA2_256', (SELECT i.type_desc, i.is_unique, i.filter_definition, i.has_filter,
                                         (SELECT COL_NAME(ic.object_id, ic.column_id) AS c, ic.is_descending_key, ic.is_included_column
                                          FROM sys.index_columns AS ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id ORDER BY ic.key_ordinal, ic.index_column_id FOR JSON PATH) AS cols
                                  FOR JSON PATH))
    FROM sys.indexes AS i JOIN sys.tables AS t ON t.object_id = i.object_id JOIN sys.schemas AS s ON s.schema_id = t.schema_id
    WHERE i.name IS NOT NULL AND s.name NOT IN ('demo', 'dbo')
    UNION ALL
    -- Модули: процедуры, функции, представления, триггеры — хэш текста
    SELECT 'modules', (s.name + '.' + o.name) COLLATE DATABASE_DEFAULT, HASHBYTES('SHA2_256', m.definition)
    FROM sys.sql_modules AS m JOIN sys.objects AS o ON o.object_id = m.object_id JOIN sys.schemas AS s ON s.schema_id = o.schema_id
    WHERE s.name NOT IN ('demo', 'dbo')
    UNION ALL
    -- Ограничения: CHECK/DEFAULT/FK
    SELECT 'constraints', (s.name + '.' + OBJECT_NAME(o.parent_object_id) + '.' + o.name) COLLATE DATABASE_DEFAULT,
           HASHBYTES('SHA2_256', ISNULL(cc.definition, ISNULL(dc.definition, CONCAT(fk.referenced_object_id, ':', fk.delete_referential_action))))
    FROM sys.objects AS o JOIN sys.schemas AS s ON s.schema_id = o.schema_id
    LEFT JOIN sys.check_constraints AS cc ON cc.object_id = o.object_id
    LEFT JOIN sys.default_constraints AS dc ON dc.object_id = o.object_id
    LEFT JOIN sys.foreign_keys AS fk ON fk.object_id = o.object_id
    WHERE o.type IN ('C', 'D', 'F') AND s.name NOT IN ('demo', 'dbo')
    UNION ALL
    -- Права ролей waybill_*
    SELECT 'permissions', r.name COLLATE DATABASE_DEFAULT,
           HASHBYTES('SHA2_256', (SELECT p.state_desc, p.permission_name, p.class, p.major_id, p.minor_id
                                  FROM sys.database_permissions AS p WHERE p.grantee_principal_id = r.principal_id
                                  ORDER BY p.class, p.major_id, p.minor_id, p.permission_name, p.state_desc FOR JSON PATH))
    FROM sys.database_principals AS r WHERE r.type = 'R' AND r.name LIKE 'waybill%'
    UNION ALL
    -- Маски
    SELECT 'masks', (OBJECT_SCHEMA_NAME(mc.object_id) + '.' + OBJECT_NAME(mc.object_id) + '.' + mc.name) COLLATE DATABASE_DEFAULT, HASHBYTES('SHA2_256', mc.masking_function)
    FROM sys.masked_columns AS mc WHERE mc.is_masked = 1
    UNION ALL
    -- RLS: политики и предикаты
    SELECT 'rls', (sp.name + ':' + OBJECT_SCHEMA_NAME(pr.target_object_id) + '.' + OBJECT_NAME(pr.target_object_id) + ':' + pr.predicate_type_desc COLLATE DATABASE_DEFAULT + ':' + ISNULL(pr.operation_desc COLLATE DATABASE_DEFAULT, '')) COLLATE DATABASE_DEFAULT,   -- *_desc — коллация каталога
           HASHBYTES('SHA2_256', CONCAT(sp.is_enabled, ':', pr.predicate_definition))
    FROM sys.security_policies AS sp JOIN sys.security_predicates AS pr ON pr.object_id = sp.object_id
    UNION ALL
    -- Настройки (без адресов/секретов)
    SELECT 'settings', st.Name COLLATE DATABASE_DEFAULT, HASHBYTES('SHA2_256', st.Value)
    FROM ops.Setting AS st WHERE st.Name NOT LIKE '%.url' AND st.Name NOT LIKE '%credential%';
GO

CREATE OR ALTER PROCEDURE ops.usp_SchemaSnapshot @Label varchar(32) = 'manual'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now datetime2(0) = SYSUTCDATETIME();
    INSERT INTO ops.SchemaSnapshot (TakenAt, Label, Component, Hash, Detail)
    SELECT @now, @Label, f.Component,
           HASHBYTES('SHA2_256', STRING_AGG(CONVERT(varchar(max), CONVERT(varchar(64), f.Hash, 2)), '|') WITHIN GROUP (ORDER BY f.Name)),   -- varchar(max): >8000 байт у modules
           JSON_ARRAYAGG(JSON_OBJECT('name': f.Name, 'hash': CONVERT(varchar(64), f.Hash, 2)) ORDER BY f.Name)
    FROM ops.tvf_SchemaFingerprints() AS f
    GROUP BY f.Component;
    PRINT CONCAT('snapshot ', @Label, ' @ ', CONVERT(varchar(30), @now, 120), ': ', @@ROWCOUNT, ' components');
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_DriftCheck @BaselineLabel varchar(32) = 'deploy'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @baseAt datetime2(0) = (SELECT MAX(TakenAt) FROM ops.SchemaSnapshot WHERE Label = @BaselineLabel);
    IF @baseAt IS NULL BEGIN PRINT CONCAT('drift: нет снимка с меткой ', @BaselineLabel); RETURN 2; END

    -- Текущее состояние во временную таблицу той же формы
    DECLARE @cur TABLE (Component varchar(32), Name nvarchar(400), Hash varchar(64));
    INSERT INTO @cur SELECT Component, Name, CONVERT(varchar(64), Hash, 2) FROM ops.tvf_SchemaFingerprints();

    DECLARE @base TABLE (Component varchar(32), Name nvarchar(400), Hash varchar(64));
    INSERT INTO @base
    SELECT s.Component, j.name, j.hash
    FROM ops.SchemaSnapshot AS s
    CROSS APPLY OPENJSON(s.Detail) WITH (name nvarchar(400) '$.name', hash varchar(64) '$.hash') AS j
    WHERE s.Label = @BaselineLabel AND s.TakenAt = @baseAt;

    DECLARE @diff TABLE (Component varchar(32), Name nvarchar(400), Change varchar(8));
    INSERT INTO @diff
    SELECT ISNULL(c.Component, b.Component), ISNULL(c.Name, b.Name),
           CASE WHEN b.Name IS NULL THEN 'added' WHEN c.Name IS NULL THEN 'dropped' ELSE 'changed' END
    FROM @cur AS c FULL JOIN @base AS b ON b.Component = c.Component AND b.Name = c.Name
    WHERE b.Name IS NULL OR c.Name IS NULL OR b.Hash <> c.Hash;

    IF NOT EXISTS (SELECT 1 FROM @diff)
    BEGIN
        PRINT CONCAT('drift: нет отличий от ', @BaselineLabel, ' @ ', CONVERT(varchar(30), @baseAt, 120));
        RETURN 0;
    END
    SELECT Component, Change, COUNT(*) AS Objects FROM @diff GROUP BY Component, Change ORDER BY Component, Change;
    SELECT Component, Name, Change FROM @diff ORDER BY Component, Change, Name;
    INSERT INTO ops.HealthLog (Severity, Issue)
    SELECT 'warn', CONCAT(N'schema drift: ', Component, N' ', Change, N' ', Name) FROM @diff;
    RETURN 1;
END;
GO
GRANT EXECUTE ON ops.usp_DriftCheck TO waybill_ops;
GRANT EXECUTE ON ops.usp_SchemaSnapshot TO waybill_ops;
GO

-- Снимок после применения главы и проверка «сам с собой»
EXEC ops.usp_SchemaSnapshot @Label = 'deploy';
EXEC ops.usp_DriftCheck @BaselineLabel = 'deploy';
GO
