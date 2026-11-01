/* 13-async/040_agent_jobs.sql
   Задания SQL Server Agent для Waybill: обслуживание секций (1-го числа), чистка inbox (ежедневно), витрина SLA (ежечасно),
   обслуживание индексов (еженедельно), digest ledger (ежедневно), снимки wait stats (каждые 5 минут); оператор и оповещение.
   Все шаги — под прикладной блокировкой job:<name> (ops.usp_RunExclusive). Без Agent — печатает предупреждение. Идемпотентен.
*/
USE msdb;
GO
SET NOCOUNT ON;
GO
-- Помощник: создать/пересоздать задание с одним T-SQL-шагом и расписанием
CREATE OR ALTER PROCEDURE dbo.usp_WaybillUpsertJob
    @Name        sysname,
    @Command     nvarchar(max),
    @FreqType    int,            -- 4 daily, 8 weekly, 16 monthly
    @FreqInterval int = 1,
    @SubdayType  int = 1,        -- 1 at the specified time, 4 minutes, 8 hours
    @SubdayInterval int = 0,
    @StartTime   int = 30000,    -- HHMMSS
    @Description nvarchar(512) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @jobId uniqueidentifier = (SELECT job_id FROM dbo.sysjobs WHERE name = @Name);
    IF @jobId IS NOT NULL EXEC dbo.sp_delete_job @job_id = @jobId;   -- пересоздание: определение задания — в скрипте, не в msdb

    EXEC dbo.sp_add_job @job_name = @Name, @enabled = 1, @description = @Description, @category_name = N'Waybill',
         @notify_level_email = 2, @notify_email_operator_name = N'waybill-ops',   -- 2: on failure
         @job_id = @jobId OUTPUT;
    EXEC dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'run', @subsystem = N'TSQL', @database_name = N'Waybill',
         @command = @Command, @retry_attempts = 1, @retry_interval = 5, @on_success_action = 1, @on_fail_action = 2;
    DECLARE @scheduleName sysname = CONCAT(@Name, N' - schedule'), @recurrence int = IIF(@FreqType IN (8, 16, 32), 1, 0);
    EXEC dbo.sp_add_jobschedule @job_id = @jobId, @name = @scheduleName,
         @freq_type = @FreqType, @freq_interval = @FreqInterval, @freq_subday_type = @SubdayType, @freq_subday_interval = @SubdayInterval,
         @freq_recurrence_factor = @recurrence, @active_start_time = @StartTime;
    EXEC dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server Agent%' AND status_desc = N'Running')
BEGIN
    PRINT 'Agent не запущен: задания не созданы (контейнер: MSSQL_AGENT_ENABLED=true; Windows: служба SQLSERVERAGENT)';
    IF OBJECT_ID(N'tempdb..#agent_skip') IS NULL CREATE TABLE #agent_skip (x int);
    RETURN;
END;
GO
IF OBJECT_ID(N'tempdb..#agent_skip') IS NOT NULL RETURN;

-- Оператор для оповещений (адрес — заглушка: Database Mail настраивается отдельно)
IF NOT EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'waybill-ops')
    EXEC dbo.sp_add_operator @name = N'waybill-ops', @enabled = 1, @email_address = N'ops@waybill.example';

-- Категория для группировки
IF NOT EXISTS (SELECT 1 FROM dbo.syscategories WHERE name = N'Waybill' AND category_class = 1)
    EXEC dbo.sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'Waybill';
GO

IF OBJECT_ID(N'tempdb..#agent_skip') IS NOT NULL RETURN;
-- Задания: каждый шаг — под прикладной блокировкой, чтобы ручной запуск не пересёкся с расписанием
EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Partition maintenance',
     @Command = N'EXEC ops.usp_RunExclusive @JobName = N''job:partition-maintenance'', @Sql = N''EXEC ops.usp_MaintainEventPartitions @MonthsAhead = 2, @RetainMonths = 12, @DryRun = 0;'';',
     @FreqType = 16, @FreqInterval = 1, @StartTime = 20000, @Description = N'SPLIT вперёд, SWITCH старых секций в архив, MERGE (глава 10)';

EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Purge inbox',
     @Command = N'EXEC ops.usp_RunExclusive @JobName = N''job:purge-inbox'', @Sql = N''EXEC ops.usp_PurgeInbox @OlderThanDays = 90, @BatchSize = 5000; EXEC ops.usp_PurgeEventSeen @OlderThanHours = 48;'';',
     @FreqType = 4, @StartTime = 30000, @Description = N'Чистка webhook-документов и ключей дедупликации';

EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Refresh CarrierSla',
     @Command = N'EXEC ops.usp_RunExclusive @JobName = N''job:sla-recalc'', @Sql = N''DECLARE @m date = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1); EXEC analytics.usp_RefreshCarrierSla @PeriodStart = @m; EXEC analytics.usp_RefreshCarrierSla @PeriodStart = DATEADD(MONTH, -1, @m);'';',
     @FreqType = 4, @SubdayType = 8, @SubdayInterval = 1, @StartTime = 1500, @Description = N'Витрина SLA за текущий и прошлый месяц (глава 9)';

EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Index maintenance',
     @Command = N'EXEC ops.usp_RunExclusive @JobName = N''job:maintain-indexes'', @Sql = N''EXEC ops.usp_MaintainIndexes @DryRun = 0; ALTER INDEX NCCI_TrackingEvent ON ship.TrackingEvent REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);'';',
     @FreqType = 8, @FreqInterval = 1, @StartTime = 10000, @Description = N'Воскресенье 01:00: индексы (глава 4), columnstore delta store';

EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Ledger digest',
     @Command = N'EXEC ops.usp_SaveLedgerDigest; EXEC ops.usp_VerifyLedger;',
     @FreqType = 4, @StartTime = 40000, @Description = N'Digest и проверка цепочки ledger (глава 11)';

EXEC dbo.usp_WaybillUpsertJob @Name = N'Waybill - Wait stats snapshot',
     @Command = N'DECLARE @id int; EXEC ops.usp_SnapshotWaitStats @Label = N''scheduled'', @SnapshotId = @id OUTPUT; DELETE FROM ops.WaitStatsSnapshot WHERE TakenAt < DATEADD(DAY, -14, SYSUTCDATETIME());',
     @FreqType = 4, @SubdayType = 4, @SubdayInterval = 5, @StartTime = 0, @Description = N'Снимки ожиданий каждые 5 минут, хранение 14 дней (глава 9)';
GO

IF OBJECT_ID(N'tempdb..#agent_skip') IS NOT NULL RETURN;
-- Оповещение: ошибки уровня 17+ (ресурсы) и deadlock-и (1205) в базе Waybill
IF NOT EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'Waybill - Severity 17+')
    EXEC dbo.sp_add_alert @name = N'Waybill - Severity 17+', @severity = 17, @database_name = N'Waybill', @enabled = 1, @delay_between_responses = 300;
IF NOT EXISTS (SELECT 1 FROM dbo.sysnotifications AS n JOIN dbo.sysalerts AS a ON a.id = n.alert_id WHERE a.name = N'Waybill - Severity 17+')
    EXEC dbo.sp_add_notification @alert_name = N'Waybill - Severity 17+', @operator_name = N'waybill-ops', @notification_method = 1;
GO

-- diagnostic: safe to re-run
IF OBJECT_ID(N'tempdb..#agent_skip') IS NOT NULL BEGIN DROP TABLE #agent_skip; RETURN; END;
SELECT j.name, j.enabled, c.name AS category, s.name AS schedule, s.freq_type, s.freq_subday_type, s.freq_subday_interval, s.active_start_time
FROM dbo.sysjobs AS j
JOIN dbo.syscategories AS c ON c.category_id = j.category_id
LEFT JOIN dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
WHERE c.name = N'Waybill' ORDER BY j.name;

-- История выполнений (после первого запуска)
SELECT TOP (20) j.name, h.run_date, h.run_time, h.run_status, h.run_duration, LEFT(h.message, 200) AS message
FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE h.step_id = 0 AND j.category_id = (SELECT category_id FROM dbo.syscategories WHERE name = N'Waybill')
ORDER BY h.run_date DESC, h.run_time DESC;

-- Ручной запуск: EXEC msdb.dbo.sp_start_job @job_name = N'Waybill - Wait stats snapshot';
GO
