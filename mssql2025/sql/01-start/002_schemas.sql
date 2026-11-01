/*
  002_schemas.sql — схемы базы Waybill и журнал миграций.
  ref       — справочники (перевозчики, регионы)
  crm       — арендаторы-магазины и их контакты
  ship      — адреса, отправления, события трекинга, история статусов
  ops       — инциденты, outbox, очереди, служебные процедуры
  bill      — тарифы (ledger)
  analytics — витрины (columnstore)
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @schemas TABLE (name sysname);
INSERT INTO @schemas (name) VALUES (N'ref'), (N'crm'), (N'ship'), (N'ops'), (N'bill'), (N'analytics');

DECLARE @name sysname, @sql nvarchar(200);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name FROM @schemas AS s
    WHERE NOT EXISTS (SELECT 1 FROM sys.schemas AS x WHERE x.name = s.name);
OPEN cur;
FETCH NEXT FROM cur INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'CREATE SCHEMA ' + QUOTENAME(@name) + N' AUTHORIZATION dbo;';
    EXEC sys.sp_executesql @sql;   -- CREATE SCHEMA обязан быть первой инструкцией пакета
    FETCH NEXT FROM cur INTO @name;
END;
CLOSE cur;
DEALLOCATE cur;
GO

-- Журнал применённых миграций: заполняют scripts/apply.ps1 и Waybill.Migrator.
IF OBJECT_ID(N'dbo.SchemaMigrations', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SchemaMigrations
    (
        ScriptName  nvarchar(260) NOT NULL,
        AppliedAt   datetime2(3)  NOT NULL CONSTRAINT DF_SchemaMigrations_AppliedAt DEFAULT SYSUTCDATETIME(),
        AppliedBy   sysname       NOT NULL CONSTRAINT DF_SchemaMigrations_AppliedBy DEFAULT ORIGINAL_LOGIN(),
        Checksum    varbinary(32) NULL,
        CONSTRAINT PK_SchemaMigrations PRIMARY KEY CLUSTERED (ScriptName)
    );
END;
GO
