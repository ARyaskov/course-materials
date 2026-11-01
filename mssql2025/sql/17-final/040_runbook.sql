/*
  040_runbook.sql — runbook обслуживания Waybill одной процедурой (глава 17).

  ops.vw_RunbookStatus — «всё ли в порядке» по регламенту: секции вперёд, возраст статистики, фрагментация, Query Store,
    бэкапы, PVS, журнал, outbox, задания, дрейф, векторная очередь, In-Memory память.
  ops.usp_Runbook @Mode = 'check' | 'daily' | 'weekly' — проверка (только чтение) или выполнение регламента:
    daily  — MaintainEventPartitions (DryRun по настройке), PurgeInbox, PurgeEventSeen, Health report, DriftCheck, EmbedPending
    weekly — MaintainIndexes, REORGANIZE columnstore, RefreshCarrierSla за текущий и прошлый месяц, SaveLedgerDigest+VerifyLedger,
             QueryStoreBaseline 'weekly', CleanupBackups
  Задания Agent глав 13/16 вызывают отдельные процедуры по расписанию; usp_Runbook — для ручного прогона и для стенда без Agent.
  Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER VIEW ops.vw_RunbookStatus
AS
SELECT 'partitions' AS Item, N'секций впереди (пустых после текущего месяца)' AS Meaning,
       CAST((SELECT COUNT(*) FROM sys.partition_range_values AS rv JOIN sys.partition_functions AS pf ON pf.function_id = rv.function_id
             WHERE pf.name = N'pf_MonthlyEvents' AND CAST(rv.value AS datetime2) > DATEADD(month, 1, SYSUTCDATETIME())) AS nvarchar(100)) AS Value,
       N'≥ 1' AS Norm
UNION ALL
SELECT 'stats-age', N'самая старая статистика ship.* (дней)',
       CAST(ISNULL(MAX(DATEDIFF(day, sp.last_updated, SYSUTCDATETIME())), 0) AS nvarchar(100)), N'≤ 7'
FROM sys.stats AS st CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) AS sp
WHERE OBJECT_SCHEMA_NAME(st.object_id) = N'ship' AND sp.rows > 10000
UNION ALL
SELECT 'index-frag', N'индексов ship.* с фрагментацией > 30 % (страниц > 1000)',
       CAST(COUNT(*) AS nvarchar(100)), N'0'
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ps
JOIN sys.objects AS o ON o.object_id = ps.object_id
WHERE o.schema_id = SCHEMA_ID(N'ship') AND ps.index_id > 0 AND ps.page_count > 1000 AND ps.avg_fragmentation_in_percent > 30
UNION ALL
SELECT 'query-store', N'Query Store: состояние / занято МБ из',
       (SELECT CONCAT(actual_state_desc, N' ', current_storage_size_mb, N'/', max_storage_size_mb) FROM sys.database_query_store_options), N'READ_WRITE, < 80 %'
UNION ALL
SELECT 'backup-full', N'часов с последнего полного бэкапа',
       CAST(ISNULL(DATEDIFF(hour, (SELECT MAX(StartedAt) FROM ops.vw_BackupHistory WHERE BackupType = 'FULL'), GETDATE()), 9999) AS nvarchar(100)), N'≤ 26'
UNION ALL
SELECT 'backup-log', N'минут с последнего бэкапа журнала',
       CAST(ISNULL(DATEDIFF(minute, (SELECT LastLogBackup FROM ops.vw_LogStatus), SYSDATETIME()), 9999) AS nvarchar(100)), N'≤ 30'
UNION ALL
SELECT 'log', N'занятость журнала %, причина', (SELECT CONCAT(ActivePct, N' ', LogReuseWait) FROM ops.vw_LogStatus), N'< 70, NOTHING/LOG_BACKUP'
UNION ALL
SELECT 'pvs', N'PVS МБ / прерванных транзакций', (SELECT CONCAT(PvsSizeMb, N' / ', AbortedTxns) FROM ops.vw_PvsStats), N'< 2048 / 0'
UNION ALL
SELECT 'outbox', N'в очереди / poison', (SELECT CONCAT((SELECT COUNT(*) FROM ops.Outbox WHERE ProcessedAt IS NULL), N' / ', (SELECT COUNT(*) FROM ops.vw_OutboxPoison))), N'< 1000 / 0'
UNION ALL
SELECT 'jobs-failed', N'упавших заданий Waybill за сутки',
       CAST((SELECT COUNT(*) FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
             WHERE h.step_id = 0 AND h.run_status = 0 AND j.name LIKE N'Waybill%' AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(day, -1, GETDATE())) AS nvarchar(100)), N'0'
UNION ALL
SELECT 'drift', N'предупреждений дрейфа в HealthLog за сутки',
       CAST((SELECT COUNT(*) FROM ops.HealthLog WHERE Issue LIKE N'schema drift%' AND TakenAt > DATEADD(day, -1, SYSUTCDATETIME())) AS nvarchar(100)), N'0'
UNION ALL
SELECT 'embeddings', N'инцидентов без вектора', CAST((SELECT COUNT(*) FROM ops.Incident WHERE Embedding IS NULL) AS nvarchar(100)), N'0 (после ночного задания)'
UNION ALL
SELECT 'xtp-memory', N'память memory-optimized таблиц, МБ',
       CAST(ISNULL((SELECT SUM(memory_allocated_for_table_kb + memory_allocated_for_indexes_kb) / 1024 FROM sys.dm_db_xtp_table_memory_stats), 0) AS nvarchar(100)), N'< лимита пула RG'
UNION ALL
SELECT 'webhooks', N'магазинов с выключенным вебхуком',
       CAST((SELECT COUNT(*) FROM crm.MerchantWebhook WHERE IsEnabled = 0) AS nvarchar(100)), N'0';
GO
GRANT SELECT ON ops.vw_RunbookStatus TO waybill_ops;
GO

CREATE OR ALTER PROCEDURE ops.usp_Runbook @Mode varchar(8) = 'check', @DryRun bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF @Mode = 'check'
    BEGIN
        SELECT * FROM ops.vw_RunbookStatus;
        RETURN;
    END

    DECLARE @log TABLE (Step varchar(60), StartedAt datetime2(0), Seconds int, Result nvarchar(200));
    DECLARE @t0 datetime2(0);

    IF @Mode IN ('daily', 'weekly')
    BEGIN
        SET @t0 = SYSUTCDATETIME(); EXEC ops.usp_MaintainEventPartitions @MonthsAhead = 2, @RetainMonths = 12, @DryRun = @DryRun;
        INSERT INTO @log VALUES ('partitions', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'dry run', N'done'));

        SET @t0 = SYSUTCDATETIME();
        IF @DryRun = 0 BEGIN EXEC ops.usp_PurgeInbox @OlderThanDays = 90, @BatchSize = 5000; EXEC ops.usp_PurgeEventSeen @OlderThanHours = 48; END
        INSERT INTO @log VALUES ('purge', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'skipped (dry run)', N'done'));

        SET @t0 = SYSUTCDATETIME(); IF @DryRun = 0 EXEC ops.usp_EmbedPendingIncidents @BatchSize = 100;
        INSERT INTO @log VALUES ('embeddings', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), N'batch 100');

        SET @t0 = SYSUTCDATETIME(); EXEC ops.usp_HealthReport;
        INSERT INTO @log VALUES ('health-report', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), CONCAT((SELECT COUNT(*) FROM ops.HealthLog WHERE TakenAt >= @t0), N' issues'));

        SET @t0 = SYSUTCDATETIME(); DECLARE @drift int; EXEC @drift = ops.usp_DriftCheck @BaselineLabel = 'deploy';
        INSERT INTO @log VALUES ('drift-check', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), CASE @drift WHEN 0 THEN N'no drift' WHEN 1 THEN N'DRIFT' ELSE N'no baseline' END);
    END

    IF @Mode = 'weekly'
    BEGIN
        SET @t0 = SYSUTCDATETIME(); EXEC ops.usp_MaintainIndexes @DryRun = @DryRun;
        INSERT INTO @log VALUES ('indexes', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'dry run', N'done'));

        SET @t0 = SYSUTCDATETIME();
        IF @DryRun = 0
        BEGIN
            ALTER INDEX NCCI_TrackingEvent ON ship.TrackingEvent REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);

        END
        INSERT INTO @log VALUES ('columnstore', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'skipped', N'reorganized'));

        SET @t0 = SYSUTCDATETIME();
        DECLARE @m date = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1), @prev date;
        SET @prev = DATEADD(month, -1, @m);
        IF @DryRun = 0 BEGIN EXEC analytics.usp_RefreshCarrierSla @PeriodStart = @m; EXEC analytics.usp_RefreshCarrierSla @PeriodStart = @prev; END
        INSERT INTO @log VALUES ('sla', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'skipped', N'2 periods'));

        SET @t0 = SYSUTCDATETIME(); IF @DryRun = 0 BEGIN EXEC ops.usp_SaveLedgerDigest; EXEC ops.usp_VerifyLedger; END
        INSERT INTO @log VALUES ('ledger', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'skipped', N'digest saved, verified'));

        SET @t0 = SYSUTCDATETIME(); EXEC ops.usp_QueryStoreBaseline @Label = 'weekly', @Hours = 168;
        INSERT INTO @log VALUES ('qs-baseline', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), N'weekly');

        SET @t0 = SYSUTCDATETIME(); IF @DryRun = 0 EXEC ops.usp_CleanupBackups;
        INSERT INTO @log VALUES ('backup-cleanup', @t0, DATEDIFF(second, @t0, SYSUTCDATETIME()), IIF(@DryRun = 1, N'skipped', N'done'));
    END

    SELECT * FROM @log;
    SELECT * FROM ops.vw_RunbookStatus;
END;
GO
GRANT EXECUTE ON ops.usp_Runbook TO waybill_ops;
GO

-- Конец деплоя: эталон дрейфа (снимок главы 16 сделан до объектов главы 17) — старые предупреждения дрейфа снимаются
EXEC ops.usp_SchemaSnapshot @Label = 'deploy';
DELETE FROM ops.HealthLog WHERE Issue LIKE N'schema drift%';
GO
EXEC ops.usp_Runbook @Mode = 'check';
EXEC ops.usp_Runbook @Mode = 'daily', @DryRun = 1;
GO
