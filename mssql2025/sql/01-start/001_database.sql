/*
  001_database.sql — создание базы Waybill (SQL Server 2025, compat 170).
  Выполняется в контексте master. Идемпотентен: повторный запуск ничего не ломает.
  Пути к файлам берутся из пути по умолчанию экземпляра (SERVERPROPERTY),
  поэтому скрипт одинаково работает на Windows-экземпляре и в контейнере Linux.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'Waybill') IS NULL
BEGIN
    DECLARE @dataPath nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260));
    DECLARE @logPath  nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS nvarchar(260));

    DECLARE @sql nvarchar(max) = N'
CREATE DATABASE Waybill
ON PRIMARY
(
    NAME = N''Waybill'',
    FILENAME = ' + QUOTENAME(@dataPath + N'Waybill.mdf', '''') + N',
    SIZE = 512MB,
    FILEGROWTH = 256MB
),
FILEGROUP FG_Events
(
    NAME = N''Waybill_Events'',
    FILENAME = ' + QUOTENAME(@dataPath + N'Waybill_Events.ndf', '''') + N',
    SIZE = 1GB,
    FILEGROWTH = 512MB
)
LOG ON
(
    NAME = N''Waybill_log'',
    FILENAME = ' + QUOTENAME(@logPath + N'Waybill_log.ldf', '''') + N',
    SIZE = 512MB,
    FILEGROWTH = 256MB
)
COLLATE Latin1_General_100_CI_AS_SC_UTF8;';

    EXEC sys.sp_executesql @sql;
END;
GO

-- Уровень совместимости 170: regex-функции, json-тип, оптимизации 2025.
ALTER DATABASE Waybill SET COMPATIBILITY_LEVEL = 170;
GO

-- Модель восстановления: на стенде SIMPLE, в продакшене FULL (см. главу 16).
IF (SELECT recovery_model_desc FROM sys.databases WHERE name = N'Waybill') <> N'SIMPLE'
    ALTER DATABASE Waybill SET RECOVERY SIMPLE;
GO

-- Версионирование строк для чтений: читатели не блокируют писателей.
IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- Accelerated Database Recovery — обязателен для optimized locking.
IF (SELECT is_accelerated_database_recovery_on FROM sys.databases WHERE name = N'Waybill') = 0
    ALTER DATABASE Waybill SET ACCELERATED_DATABASE_RECOVERY = ON;
GO

-- Optimized locking (SQL Server 2025): TID-блокировки + lock after qualification.
IF DATABASEPROPERTYEX(N'Waybill', 'IsOptimizedLockingOn') = 0
    ALTER DATABASE Waybill SET OPTIMIZED_LOCKING = ON;
GO

-- Query Store включён с первого дня: история планов и ожиданий.
ALTER DATABASE Waybill SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1024,
    INTERVAL_LENGTH_MINUTES = 15,
    WAIT_STATS_CAPTURE_MODE = ON
);
GO

-- Автоматические статистики и асинхронное обновление — норма для OLTP.
ALTER DATABASE Waybill SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE Waybill SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE Waybill SET AUTO_UPDATE_STATISTICS_ASYNC ON;
GO
