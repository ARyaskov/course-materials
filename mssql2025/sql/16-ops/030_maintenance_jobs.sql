/*
  030_maintenance_jobs.sql — задания Agent для эксплуатации (глава 16), по образцу главы 13 (dbo.usp_WaybillUpsertJob).

    Waybill - Backup FULL          ежедневно 01:00     ops.usp_BackupDatabase 'FULL' + usp_VerifyLastBackup
    Waybill - Backup DIFF          ежедневно 13:00     ops.usp_BackupDatabase 'DIFF'
    Waybill - Backup LOG           каждые 15 минут     ops.usp_BackupDatabase 'LOG'
    Waybill - Integrity check      воскресенье 04:00   DBCC CHECKDB WITH NO_INFOMSGS, DATA_PURITY
    Waybill - Backup cleanup       ежедневно 05:00     удаление файлов старше 14 дней (xp_delete_files) — только для DISK
    Waybill - Health report        каждые 30 минут     ops.usp_LogHealth → ops.HealthLog
  Без Agent (не запущен) — пропуск с сообщением. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'ops.HealthLog', N'U') IS NULL
CREATE TABLE ops.HealthLog
(
    HealthLogId bigint IDENTITY CONSTRAINT PK_HealthLog PRIMARY KEY,
    TakenAt     datetime2(0) NOT NULL CONSTRAINT DF_HealthLog_TakenAt DEFAULT SYSUTCDATETIME(),
    Severity    varchar(8)   NOT NULL,
    Issue       nvarchar(400) NOT NULL
);
GO

INSERT INTO ops.Setting (Name, Value) SELECT 'backup.retain_days', N'14' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'backup.retain_days');
GO

-- Чистка старых файлов бэкапов (DISK); для URL — политика жизненного цикла в хранилище
CREATE OR ALTER PROCEDURE ops.usp_CleanupBackups @RetainDays int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (SELECT Value FROM ops.Setting WHERE Name = 'backup.url') <> N'' BEGIN PRINT 'backup.url задан: чистка — политикой хранилища'; RETURN; END
    SET @RetainDays = ISNULL(@RetainDays, CAST((SELECT Value FROM ops.Setting WHERE Name = 'backup.retain_days') AS int));
    DECLARE @path nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260));
    DECLARE @cutoff datetime = DATEADD(day, -@RetainDays, GETDATE());
    -- xp_delete_file удаляет только файлы бэкапов (проверяет заголовок): 0 = backup files, расширение без точки
    EXEC master.dbo.xp_delete_file 0, @path, N'bak', @cutoff, 0;
    EXEC master.dbo.xp_delete_file 0, @path, N'trn', @cutoff, 0;
    -- История msdb: старше 90 дней
    DECLARE @hist datetime = DATEADD(day, -90, GETDATE());
    EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @hist;
    DELETE FROM ops.BackupRun WHERE StartedAt < @hist;
    PRINT CONCAT('cleanup: файлы старше ', @RetainDays, ' дней удалены из ', @path);
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_HealthReport
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @issues TABLE (Severity varchar(8), Issue nvarchar(400));
    INSERT INTO @issues EXEC ops.usp_LogHealth;
    INSERT INTO ops.HealthLog (Severity, Issue) SELECT Severity, Issue FROM @issues;
    -- Бэкап: последний FULL старше 26 часов — ошибка; последний LOG старше 30 минут ловит usp_LogHealth
    INSERT INTO ops.HealthLog (Severity, Issue)
    SELECT 'error', CONCAT(N'полный бэкап старше 26 ч: ', ISNULL(CONVERT(nvarchar(30), MAX(StartedAt), 120), N'никогда'))
    FROM ops.vw_BackupHistory WHERE BackupType = 'FULL'
    HAVING MAX(StartedAt) < DATEADD(hour, -26, GETDATE()) OR MAX(StartedAt) IS NULL;
    -- Outbox: poison-сообщения (глава 8)
    INSERT INTO ops.HealthLog (Severity, Issue)
    SELECT 'warn', CONCAT(N'outbox poison: ', COUNT(*)) FROM ops.vw_OutboxPoison HAVING COUNT(*) > 0;
    -- Задания Agent, упавшие за сутки
    INSERT INTO ops.HealthLog (Severity, Issue)
    SELECT 'error', CONCAT(N'job failed: ', j.name, N' — ', LEFT(h.message, 200))
    FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
    WHERE h.step_id = 0 AND h.run_status = 0 AND j.name LIKE N'Waybill%'
      AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(day, -1, GETDATE());
    DELETE FROM ops.HealthLog WHERE TakenAt < DATEADD(day, -30, SYSUTCDATETIME());
END;
GO
GRANT EXECUTE ON ops.usp_HealthReport TO waybill_ops;
GRANT SELECT ON ops.HealthLog TO waybill_ops;
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%' AND status_desc = N'Running')
BEGIN
    PRINT 'Agent не запущен: задания эксплуатации не созданы';
    IF OBJECT_ID(N'tempdb..#agent_skip16') IS NULL CREATE TABLE #agent_skip16 (x int);
END
GO
IF OBJECT_ID(N'tempdb..#agent_skip16') IS NULL AND OBJECT_ID(N'msdb.dbo.usp_WaybillUpsertJob', N'P') IS NOT NULL
BEGIN
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Backup FULL',
         @Command = N'EXEC ops.usp_BackupDatabase @Type = ''FULL''; EXEC ops.usp_VerifyLastBackup;',
         @FreqType = 4, @StartTime = 10000, @Description = N'Полный бэкап + RESTORE VERIFYONLY (глава 16)';
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Backup DIFF',
         @Command = N'EXEC ops.usp_BackupDatabase @Type = ''DIFF'';',
         @FreqType = 4, @StartTime = 130000, @Description = N'Разностный бэкап';
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Backup LOG',
         @Command = N'EXEC ops.usp_BackupDatabase @Type = ''LOG'';',
         @FreqType = 4, @SubdayType = 4, @SubdayInterval = 15, @StartTime = 0, @Description = N'Журнал каждые 15 минут (RPO)';
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Integrity check',
         @Command = N'DBCC CHECKDB (Waybill) WITH NO_INFOMSGS, DATA_PURITY;',
         @FreqType = 8, @FreqInterval = 1, @StartTime = 40000, @Description = N'CHECKDB по воскресеньям';
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Backup cleanup',
         @Command = N'EXEC ops.usp_CleanupBackups;',
         @FreqType = 4, @StartTime = 50000, @Description = N'Удаление бэкапов старше backup.retain_days';
    EXEC msdb.dbo.usp_WaybillUpsertJob @Name = N'Waybill - Health report',
         @Command = N'EXEC ops.usp_HealthReport;',
         @FreqType = 4, @SubdayType = 4, @SubdayInterval = 30, @StartTime = 0, @Description = N'Журнал, бэкапы, outbox, упавшие задания → ops.HealthLog';
    PRINT 'jobs: Backup FULL/DIFF/LOG, Integrity check, Backup cleanup, Health report';
END
GO
IF OBJECT_ID(N'tempdb..#agent_skip16') IS NOT NULL DROP TABLE #agent_skip16;
GO

EXEC ops.usp_HealthReport;
SELECT TOP (20) * FROM ops.HealthLog ORDER BY HealthLogId DESC;
GO
