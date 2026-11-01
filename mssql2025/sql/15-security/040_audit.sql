/*
  040_audit.sql — SQL Audit для Waybill.

  Server audit Waybill_Audit → файлы в InstanceDefaultLogPath\WaybillAudit\ (ротация 20 × 100 МБ), ON_FAILURE = CONTINUE.
  Server audit specification Waybill_ServerSpec: неудачные логины, изменения логинов/ролей сервера, изменения audit.
  Database audit specification Waybill_DbSpec:
    - SELECT на ship.Address и ship.RecipientContact (PII) — кто читал;
    - EXECUTE на схему sec (управление контекстом) — кто менял арендатора;
    - SCHEMA_OBJECT_CHANGE_GROUP, DATABASE_ROLE_MEMBER_CHANGE_GROUP, DATABASE_PERMISSION_CHANGE_GROUP,
      DATABASE_PRINCIPAL_CHANGE_GROUP, DATABASE_OBJECT_PERMISSION_CHANGE_GROUP.
  Чтение: sec.tvf_AuditEvents(@Since) поверх sys.fn_get_audit_file; sec.vw_AuditPiiReads.
  Требует CONTROL SERVER (ALTER ANY SERVER AUDIT) — иначе серверная часть пропускается; ops.Setting 'security.audit' = 0 выключает.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @audit bit = IIF((SELECT Value FROM ops.Setting WHERE Name = 'security.audit') = N'1', 1, 0);
IF HAS_PERMS_BY_NAME(NULL, NULL, 'CONTROL SERVER') <> 1
BEGIN
    PRINT 'audit skipped: нет CONTROL SERVER';
    SET @audit = 0;
END

IF @audit = 1
BEGIN
    BEGIN TRY
        DECLARE @path nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(260)) + N'WaybillAudit\';
        DECLARE @sql nvarchar(max);

        -- Каталог: xp_create_subdir создаёт, если нет (нужны права службы SQL Server на путь)
        BEGIN TRY EXEC master.sys.xp_create_subdir @path; END TRY BEGIN CATCH END CATCH

        IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Waybill_Audit')
        BEGIN
            SET @sql = N'USE master;
CREATE SERVER AUDIT Waybill_Audit
TO FILE (FILEPATH = ' + QUOTENAME(@path, '''') + N', MAXSIZE = 100 MB, MAX_ROLLOVER_FILES = 20, RESERVE_DISK_SPACE = OFF)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);';
            EXEC sys.sp_executesql @sql;
        END
        IF NOT EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'Waybill_ServerSpec')
            EXEC sys.sp_executesql N'USE master;
CREATE SERVER AUDIT SPECIFICATION Waybill_ServerSpec FOR SERVER AUDIT Waybill_Audit
    ADD (FAILED_LOGIN_GROUP),
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
    ADD (AUDIT_CHANGE_GROUP),
    ADD (SERVER_PERMISSION_CHANGE_GROUP)
WITH (STATE = ON);';

        -- Спецификация базы: пересоздаём, если состав изменился (ALTER требует STATE = OFF)
        IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'Waybill_DbSpec')
        BEGIN
            EXEC sys.sp_executesql N'ALTER DATABASE AUDIT SPECIFICATION Waybill_DbSpec WITH (STATE = OFF);';
            EXEC sys.sp_executesql N'DROP DATABASE AUDIT SPECIFICATION Waybill_DbSpec;';
        END
        EXEC sys.sp_executesql N'
CREATE DATABASE AUDIT SPECIFICATION Waybill_DbSpec FOR SERVER AUDIT Waybill_Audit
    ADD (SELECT ON OBJECT::ship.Address BY public),
    ADD (SELECT ON OBJECT::ship.RecipientContact BY public),
    ADD (EXECUTE ON SCHEMA::sec BY public),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_PRINCIPAL_IMPERSONATION_GROUP)
WITH (STATE = ON);';

        IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Waybill_Audit' AND is_state_enabled = 0)
            EXEC sys.sp_executesql N'USE master; ALTER SERVER AUDIT Waybill_Audit WITH (STATE = ON);';
        PRINT CONCAT('audit Waybill_Audit → ', @path);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('audit skipped: ', ERROR_MESSAGE());
    END CATCH
END
ELSE IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Waybill_Audit' AND is_state_enabled = 1)
BEGIN
    EXEC sys.sp_executesql N'USE master; ALTER SERVER AUDIT Waybill_Audit WITH (STATE = OFF);';
    PRINT 'audit Waybill_Audit: STATE = OFF (security.audit = 0)';
END
GO

-- Чтение журнала ---------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION sec.tvf_AuditEvents (@Since datetime2(0))
RETURNS TABLE
AS
RETURN
    SELECT a.event_time AS EventTime, a.action_id AS ActionId, a.class_type AS ClassType, a.succeeded AS Succeeded,
           a.server_principal_name AS ServerPrincipal, a.database_principal_name AS DbPrincipal,
           a.session_server_principal_name AS SessionPrincipal,          -- кто на самом деле (EXECUTE AS видно здесь)
           a.database_name AS DatabaseName, a.schema_name AS SchemaName, a.object_name AS ObjectName,
           a.application_name AS AppName, a.client_ip AS ClientIp, a.session_id AS SessionId,
           LEFT(a.statement, 400) AS Statement, a.additional_information AS Additional
    FROM sys.fn_get_audit_file(
            CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(260)) + N'WaybillAudit\*.sqlaudit', DEFAULT, DEFAULT) AS a
    WHERE a.event_time >= @Since;
GO
GRANT SELECT ON sec.tvf_AuditEvents TO waybill_ops;
GO

-- Кто читал PII за сутки: по пользователю, приложению и объекту
CREATE OR ALTER VIEW sec.vw_AuditPiiReads
AS
SELECT DATE_BUCKET(hour, 1, EventTime) AS Hour, SessionPrincipal, DbPrincipal, AppName, SchemaName + N'.' + ObjectName AS ObjectName,
       COUNT(*) AS Reads, MAX(EventTime) AS LastRead
FROM sec.tvf_AuditEvents(DATEADD(day, -1, SYSUTCDATETIME()))
WHERE ActionId = 'SL' AND ObjectName IN (N'Address', N'RecipientContact')
GROUP BY DATE_BUCKET(hour, 1, EventTime), SessionPrincipal, DbPrincipal, AppName, SchemaName + N'.' + ObjectName;
GO

-- Состояние
SELECT name, is_state_enabled, on_failure_desc, queue_delay FROM sys.server_audits WHERE name = N'Waybill_Audit';
SELECT s.name, s.is_state_enabled, d.audit_action_name, d.class_desc, OBJECT_NAME(d.major_id) AS ObjectName, d.audited_principal_id
FROM sys.database_audit_specifications AS s
JOIN sys.database_audit_specification_details AS d ON d.database_specification_id = s.database_specification_id
WHERE s.name = N'Waybill_DbSpec';
GO

-- Проверка: чтение адреса попадает в журнал (QUEUE_DELAY = 1 с — подождать)
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'Waybill_Audit' AND is_state_enabled = 1)
BEGIN
    SELECT TOP (1) AddressId FROM ship.Address;
    WAITFOR DELAY '00:00:02';
    SELECT TOP (5) EventTime, ActionId, SessionPrincipal, DbPrincipal, ObjectName, AppName, Statement
    FROM sec.tvf_AuditEvents(DATEADD(minute, -5, SYSUTCDATETIME()))
    WHERE ObjectName = N'Address'
    ORDER BY EventTime DESC;
END
GO
