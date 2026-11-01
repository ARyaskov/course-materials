/*
  010_principals.sql — модель доступа Waybill (глава 15).

  Схема sec (объекты безопасности), роли базы:
    waybill_api       — сервисная учётка API: EXECUTE на ops/ship/analytics, SELECT на ref/crm; таблицы напрямую не читает
    waybill_ingest    — обход RLS для маршрутов приёма событий (SESSION_CONTEXT('MerchantId') не задан)
    waybill_readonly  — аналитики/поддержка: SELECT на ship/crm/ref/analytics/bill, данные PII маскируются (030)
    waybill_ops       — эксплуатация: readonly + EXECUTE ops.usp_* обслуживания + UNMASK
  Логины (только если есть право ALTER ANY LOGIN; пароли — для стенда, в проде — из менеджера секретов):
    waybill_api → пользователь waybill_api_svc (роли waybill_api, waybill_ingest); имя пользователя ≠ имени роли (общее пространство имён)
    waybill_reader → пользователь waybill_reader (роль waybill_readonly)
  Пользователь без логина waybill_merchant_test — для проверки RLS через EXECUTE AS (020).
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'sec')
    EXEC sys.sp_executesql N'CREATE SCHEMA sec AUTHORIZATION dbo;';
GO

-- Роли базы ---------------------------------------------------------------------------------------
DECLARE @roles TABLE (name sysname);
INSERT INTO @roles VALUES (N'waybill_api'), (N'waybill_ingest'), (N'waybill_readonly'), (N'waybill_ops');
DECLARE @r sysname, @sql nvarchar(400);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT r.name FROM @roles AS r WHERE NOT EXISTS (SELECT 1 FROM sys.database_principals AS p WHERE p.name = r.name AND p.type = 'R');
OPEN cur; FETCH NEXT FROM cur INTO @r;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'CREATE ROLE ' + QUOTENAME(@r) + N' AUTHORIZATION dbo;';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM cur INTO @r;
END
CLOSE cur; DEALLOCATE cur;
GO

-- Права ролей: схема — единица выдачи -------------------------------------------------------------
-- waybill_api: только процедуры/функции + справочники. Таблицы ship/ops напрямую не видны:
-- доступ к ним даёт ownership chaining (владелец процедур и таблиц — dbo).
GRANT EXECUTE ON SCHEMA::ops       TO waybill_api;
GRANT EXECUTE ON SCHEMA::ship      TO waybill_api;
GRANT EXECUTE ON SCHEMA::analytics TO waybill_api;
GRANT SELECT  ON SCHEMA::ref       TO waybill_api;
GRANT SELECT  ON SCHEMA::crm       TO waybill_api;
-- Табличные типы для TVP
GRANT EXECUTE ON TYPE::ops.tt_TrackingEventIn TO waybill_api;
-- Точечные исключения, где репозитории читают таблицы напрямую (глава 12): версия строки, список, outbox
GRANT SELECT ON ship.Shipment TO waybill_api;
GRANT SELECT ON ship.ShipmentHistory TO waybill_api;
GRANT SELECT, INSERT ON ops.Incident TO waybill_api;
GRANT SELECT, INSERT, UPDATE ON ops.Outbox TO waybill_api;
GRANT SELECT, INSERT ON ops.OutboxDelivery TO waybill_api;
GRANT INSERT ON ops.EventImportRaw TO waybill_api;      -- SqlBulkCopy
GRANT SELECT ON ops.Setting TO waybill_api;
-- Адреса и PII — только через процедуры: явный DENY переживёт любые будущие GRANT на схему
DENY SELECT ON ship.Address TO waybill_api;
GO

-- waybill_readonly: чтение всего прикладного, PII маскируется (030_masking.sql)
GRANT SELECT ON SCHEMA::ref       TO waybill_readonly;
GRANT SELECT ON SCHEMA::crm       TO waybill_readonly;
GRANT SELECT ON SCHEMA::ship      TO waybill_readonly;
GRANT SELECT ON SCHEMA::bill      TO waybill_readonly;
GRANT SELECT ON SCHEMA::analytics TO waybill_readonly;
GRANT SELECT ON ops.vw_OutboxStats TO waybill_readonly;
GRANT SELECT ON ops.vw_QueryStoreTop TO waybill_readonly;
GRANT SELECT ON ops.vw_QueryStoreRegressions TO waybill_readonly;
GRANT SHOWPLAN TO waybill_readonly;
DENY INSERT, UPDATE, DELETE ON SCHEMA::ship TO waybill_readonly;
GO

-- waybill_ops: readonly + обслуживание + UNMASK (030) + просмотр состояния сервера
ALTER ROLE waybill_readonly ADD MEMBER waybill_ops;
GRANT EXECUTE ON SCHEMA::ops TO waybill_ops;
GRANT SELECT  ON SCHEMA::ops TO waybill_ops;
GRANT EXECUTE ON SCHEMA::analytics TO waybill_ops;
GRANT VIEW DATABASE STATE TO waybill_ops;
GO

-- Логины и пользователи -------------------------------------------------------------------------
-- Пароли ниже — для стенда. В проде: CREATE LOGIN … WITH PASSWORD = <из секрета>, CHECK_POLICY = ON.
DECLARE @canCreateLogin bit = IIF(HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY LOGIN') = 1, 1, 0);
IF @canCreateLogin = 1
BEGIN
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'waybill_api')
            CREATE LOGIN waybill_api WITH PASSWORD = N'Waybill_Api_2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = Waybill;
        IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'waybill_reader')
            CREATE LOGIN waybill_reader WITH PASSWORD = N'Waybill_Reader_2026!', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = Waybill;
        PRINT 'logins waybill_api / waybill_reader: ok';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('logins skipped: ', ERROR_MESSAGE());
        SET @canCreateLogin = 0;
    END CATCH
END
ELSE
    PRINT 'logins skipped: no ALTER ANY LOGIN (создайте waybill_api / waybill_reader вручную)';

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'waybill_api')
   AND NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_api_svc' AND type = 'S')
    CREATE USER waybill_api_svc FOR LOGIN waybill_api WITH DEFAULT_SCHEMA = ops;   -- имя ≠ имени роли: пользователи и роли базы делят одно пространство имён
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'waybill_reader')
   AND NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_reader' AND type = 'S')
    CREATE USER waybill_reader FOR LOGIN waybill_reader WITH DEFAULT_SCHEMA = ship;

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_api_svc' AND type = 'S')
BEGIN
    ALTER ROLE waybill_api    ADD MEMBER waybill_api_svc;
    ALTER ROLE waybill_ingest ADD MEMBER waybill_api_svc;
END
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_reader' AND type = 'S')
    ALTER ROLE waybill_readonly ADD MEMBER waybill_reader;
GO

-- Пользователь без логина: имитирует API от имени магазина в тестах RLS (EXECUTE AS USER)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'waybill_merchant_test')
    CREATE USER waybill_merchant_test WITHOUT LOGIN WITH DEFAULT_SCHEMA = ops;
ALTER ROLE waybill_api ADD MEMBER waybill_merchant_test;      -- без waybill_ingest: обхода RLS у него нет
GO

-- Настройки безопасности проекта
INSERT INTO ops.Setting (Name, Value) SELECT 'security.tde', N'0' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'security.tde');
INSERT INTO ops.Setting (Name, Value) SELECT 'security.audit', N'1' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'security.audit');
INSERT INTO ops.Setting (Name, Value) SELECT 'security.rls', N'1' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'security.rls');
GO

-- Диагностика: кто что может ---------------------------------------------------------------------
CREATE OR ALTER VIEW sec.vw_RolePermissions
AS
SELECT r.name AS RoleName, p.state_desc AS State, p.permission_name AS Permission,
       p.class_desc AS Class,
       CASE p.class
            WHEN 0 THEN N'DATABASE'
            WHEN 1 THEN CONCAT(OBJECT_SCHEMA_NAME(p.major_id), N'.', OBJECT_NAME(p.major_id))
            WHEN 3 THEN SCHEMA_NAME(p.major_id)
            WHEN 6 THEN TYPE_NAME(p.major_id)
            ELSE CAST(p.major_id AS nvarchar(20)) END AS Securable
FROM sys.database_permissions AS p
JOIN sys.database_principals AS r ON r.principal_id = p.grantee_principal_id
WHERE r.type = 'R' AND r.name LIKE N'waybill%';
GO

CREATE OR ALTER VIEW sec.vw_RoleMembers
AS
SELECT r.name AS RoleName, m.name AS MemberName, m.type_desc AS MemberType, m.authentication_type_desc AS AuthType
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE N'waybill%';
GO

SELECT * FROM sec.vw_RoleMembers ORDER BY RoleName, MemberName;
SELECT RoleName, State, Permission, Securable FROM sec.vw_RolePermissions ORDER BY RoleName, Securable, Permission;
GO
