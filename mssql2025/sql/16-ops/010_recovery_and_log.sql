/*
  010_recovery_and_log.sql — модель восстановления, журнал транзакций, ADR/PVS (глава 16).

  - Waybill: RECOVERY FULL (point-in-time), ADR включён с главы 8 — здесь проверяется и включается, если нет.
  - ops.vw_LogStatus     — размер/занятость журнала, VLF, log_reuse_wait_desc, последний бэкап журнала.
  - ops.vw_PvsStats      — persistent version store: размер, самая старая транзакция, что держит очистку.
  - ops.usp_LogHealth    — одна процедура для панели и smoke-проверок: печатает предупреждения.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Модель восстановления и ADR ----------------------------------------------------------------------
IF (SELECT recovery_model_desc FROM sys.databases WHERE database_id = DB_ID()) <> N'FULL'
BEGIN
    ALTER DATABASE Waybill SET RECOVERY FULL;
    PRINT 'recovery model → FULL (первый полный бэкап после этого начинает цепочку журналов)';
END
IF (SELECT is_accelerated_database_recovery_on FROM sys.databases WHERE database_id = DB_ID()) = 0
BEGIN
    ALTER DATABASE Waybill SET ACCELERATED_DATABASE_RECOVERY = ON;
    PRINT 'ADR → ON';
END
GO

-- Журнал ---------------------------------------------------------------------------------------------
CREATE OR ALTER VIEW ops.vw_LogStatus
AS
SELECT d.name AS DatabaseName, d.recovery_model_desc AS RecoveryModel, d.log_reuse_wait_desc AS LogReuseWait,
       ls.total_log_size_mb AS LogSizeMb, ls.active_log_size_mb AS ActiveLogMb,
       CAST(ls.active_log_size_mb * 100.0 / NULLIF(ls.total_log_size_mb, 0) AS decimal(5, 1)) AS ActivePct,
       ls.total_vlf_count AS Vlfs, ls.active_vlf_count AS ActiveVlfs,
       ls.log_since_last_log_backup_mb AS SinceLastLogBackupMb,
       ls.log_backup_time AS LastLogBackup,
       ls.log_since_last_checkpoint_mb AS SinceCheckpointMb,
       ls.log_truncation_holdup_reason AS TruncationHoldup,
       ls.log_recovery_size_mb AS RecoverySizeMb
FROM sys.databases AS d
CROSS APPLY sys.dm_db_log_stats(d.database_id) AS ls
WHERE d.database_id = DB_ID();
GO

-- PVS (ADR) -------------------------------------------------------------------------------------------
CREATE OR ALTER VIEW ops.vw_PvsStats
AS
SELECT DB_NAME(p.database_id) AS DatabaseName,
       CAST(p.persistent_version_store_size_kb / 1024.0 AS decimal(12, 1)) AS PvsSizeMb,
       p.online_index_version_store_size_kb / 1024 AS OnlineIndexVsMb,
       p.current_aborted_transaction_count AS AbortedTxns,
       p.oldest_active_transaction_id AS OldestActiveTxnId,
       p.oldest_aborted_transaction_id AS OldestAbortedTxnId,
       p.min_transaction_timestamp AS MinTxnTimestamp,
       p.pvs_off_row_page_skipped_low_water_mark AS SkippedLowWaterMark,
       p.pvs_off_row_page_skipped_min_useful_xts AS SkippedMinUsefulXts,
       p.pvs_off_row_page_skipped_transaction_not_cleaned AS SkippedTxnNotCleaned
FROM sys.dm_tran_persistent_version_store_stats AS p
WHERE p.database_id = DB_ID();
GO

-- Что держит очистку версий / усечение журнала: самая старая активная транзакция и её сессия
CREATE OR ALTER VIEW ops.vw_OldestTransactions
AS
SELECT TOP (10) at.transaction_id, at.name, at.transaction_begin_time,
       DATEDIFF(second, at.transaction_begin_time, SYSDATETIME()) AS AgeSeconds,
       st.session_id, s.login_name, s.program_name, s.host_name, s.status AS SessionStatus,
       (SELECT text FROM sys.dm_exec_sql_text(c.most_recent_sql_handle)) AS LastSql
FROM sys.dm_tran_active_transactions AS at
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = at.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
LEFT JOIN sys.dm_exec_connections AS c ON c.session_id = s.session_id
WHERE st.is_user_transaction = 1
ORDER BY at.transaction_begin_time;
GO

-- Диагностика одной процедурой ----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE ops.usp_LogHealth
    @MaxActivePct decimal(5, 1) = 70, @MaxVlfs int = 200, @MaxPvsMb int = 2048, @MaxLogBackupAgeMinutes int = 30
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @issues TABLE (Severity varchar(8), Issue nvarchar(400));

    INSERT INTO @issues
    SELECT 'warn', CONCAT(N'журнал занят на ', ActivePct, N'% (', ActiveLogMb, N' МБ): ', LogReuseWait) FROM ops.vw_LogStatus WHERE ActivePct > @MaxActivePct
    UNION ALL
    SELECT 'warn', CONCAT(N'VLF: ', Vlfs, N' — фрагментированный журнал (SHRINK + один рост)') FROM ops.vw_LogStatus WHERE Vlfs > @MaxVlfs
    UNION ALL
    SELECT 'warn', CONCAT(N'log_reuse_wait: ', LogReuseWait) FROM ops.vw_LogStatus WHERE LogReuseWait NOT IN (N'NOTHING', N'CHECKPOINT')
    UNION ALL
    SELECT 'error', CONCAT(N'бэкап журнала старше ', @MaxLogBackupAgeMinutes, N' мин: ', ISNULL(CONVERT(nvarchar(30), LastLogBackup, 120), N'никогда'))
    FROM ops.vw_LogStatus WHERE RecoveryModel = N'FULL' AND (LastLogBackup IS NULL OR LastLogBackup < DATEADD(minute, -@MaxLogBackupAgeMinutes, SYSDATETIME()))
    UNION ALL
    SELECT 'warn', CONCAT(N'PVS: ', PvsSizeMb, N' МБ; прерванных транзакций: ', AbortedTxns) FROM ops.vw_PvsStats WHERE PvsSizeMb > @MaxPvsMb
    UNION ALL
    SELECT 'warn', CONCAT(N'транзакция открыта ', AgeSeconds, N' с: session ', session_id, N' (', program_name, N')') FROM ops.vw_OldestTransactions WHERE AgeSeconds > 300;

    IF NOT EXISTS (SELECT 1 FROM @issues) PRINT 'log health: ok';
    SELECT * FROM @issues ORDER BY CASE Severity WHEN 'error' THEN 0 ELSE 1 END, Issue;
END;
GO
GRANT EXECUTE ON ops.usp_LogHealth TO waybill_ops;
GRANT SELECT ON ops.vw_LogStatus TO waybill_ops;
GRANT SELECT ON ops.vw_PvsStats TO waybill_ops;
GO

SELECT * FROM ops.vw_LogStatus;
SELECT * FROM ops.vw_PvsStats;
EXEC ops.usp_LogHealth;
GO

-- Демонстрация: как батч раздувает журнал и что показывает log_reuse_wait ----------------------------
-- (в SIMPLE журнал усекается на checkpoint, в FULL — только после BACKUP LOG; выполняется на demo-таблице)
IF OBJECT_ID(N'demo.LogBloat', N'U') IS NOT NULL DROP TABLE demo.LogBloat;
CREATE TABLE demo.LogBloat (Id int IDENTITY PRIMARY KEY, Payload char(2000) NOT NULL DEFAULT REPLICATE('x', 2000));
GO
DECLARE @before decimal(12, 1) = (SELECT ActiveLogMb FROM ops.vw_LogStatus);
INSERT INTO demo.LogBloat (Payload) SELECT REPLICATE('x', 2000) FROM GENERATE_SERIES(1, 20000);   -- ~40 МБ журнала одной инструкцией
SELECT @before AS ActiveLogMbBefore, ActiveLogMb AS ActiveLogMbAfter, LogReuseWait, SinceLastLogBackupMb FROM ops.vw_LogStatus;   -- в FULL активный журнал не усечётся до BACKUP LOG
DROP TABLE demo.LogBloat;
GO
