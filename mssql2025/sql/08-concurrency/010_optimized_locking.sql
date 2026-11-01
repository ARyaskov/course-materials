/*
  010_optimized_locking.sql — проверка и включение RCSI / ADR / optimized locking / snapshot isolation (уроки 8.2, 8.4). Идемпотентен.
  Все настройки уже выставлены в 001_database.sql; здесь — контроль и ALLOW_SNAPSHOT_ISOLATION для отчётных транзакций.
*/
USE master;
GO
SET NOCOUNT ON;
GO

IF (SELECT snapshot_isolation_state FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
IF (SELECT is_accelerated_database_recovery_on FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET ACCELERATED_DATABASE_RECOVERY = ON;
IF DATABASEPROPERTYEX(N'Waybill', 'IsOptimizedLockingOn') = 0
    ALTER DATABASE Waybill SET OPTIMIZED_LOCKING = ON WITH ROLLBACK IMMEDIATE;
GO

SELECT name, is_read_committed_snapshot_on, snapshot_isolation_state_desc, is_accelerated_database_recovery_on,
       DATABASEPROPERTYEX(name, 'IsOptimizedLockingOn') AS optimized_locking
FROM sys.databases WHERE name = N'Waybill';
GO

USE Waybill;
GO
-- Демонстрация TID-блокировки: одна XACT-блокировка на транзакцию вместо KEY на каждую строку
BEGIN TRANSACTION;
UPDATE demo.Shipment SET Status = Status WHERE ShipmentId <= 1000;
SELECT resource_type, request_mode, COUNT(*) AS locks
FROM sys.dm_tran_locks WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode;
ROLLBACK;
GO
