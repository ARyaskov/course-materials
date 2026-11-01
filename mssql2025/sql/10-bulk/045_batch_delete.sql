/* 10-bulk/045_batch_delete.sql
   Батчевое удаление и обновление: ops.usp_PurgeInbox (webhook-документы и отклонённые события старше N дней) —
   DELETE TOP (N) в цикле с контролем журнала и пауза; батчевое обновление с OUTPUT. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Индексы под условие удаления: без них каждый батч — скан
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WebhookInbox_ReceivedAt' AND object_id = OBJECT_ID(N'ops.WebhookInbox'))
    CREATE INDEX IX_WebhookInbox_ReceivedAt ON ops.WebhookInbox (ReceivedAt) INCLUDE (Status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_RejectedEvent_Inbox' AND object_id = OBJECT_ID(N'ops.RejectedEvent'))
    CREATE INDEX IX_RejectedEvent_Inbox ON ops.RejectedEvent (InboxId);
GO

CREATE OR ALTER PROCEDURE ops.usp_PurgeInbox
    @OlderThanDays int = 90,
    @BatchSize     int = 5000,
    @MaxBatches    int = 1000,
    @PauseMs       int = 200,
    @MaxLogPercent decimal(5, 1) = 70.0      -- остановиться, если журнал заполнен сильнее
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @cutoff datetime2(3) = DATEADD(DAY, -@OlderThanDays, SYSUTCDATETIME());
    DECLARE @batch int = 0, @deletedInbox int = 0, @deletedRejected int = 0, @rows int = 1;
    DECLARE @pause char(12) = CONCAT('00:00:00.', RIGHT(CONCAT('000', @PauseMs), 3));
    DECLARE @ids TABLE (InboxId bigint PRIMARY KEY);

    WHILE @rows > 0 AND @batch < @MaxBatches
    BEGIN
        -- Контроль журнала: при FULL и отставшем бэкапе журнала удаление раздует его
        IF (SELECT log_since_last_log_backup_mb * 100.0 / NULLIF(total_log_size_mb, 0) FROM sys.dm_db_log_stats(DB_ID())) > @MaxLogPercent
        BEGIN
            PRINT 'purge paused: log usage above threshold';
            BREAK;
        END;

        DELETE FROM @ids;
        INSERT INTO @ids (InboxId)
        SELECT TOP (@BatchSize) InboxId FROM ops.WebhookInbox
        WHERE ReceivedAt < @cutoff AND Status IN (3, 5)          -- processed / duplicate; rejected и failed храним дольше
        ORDER BY ReceivedAt;                                      -- по индексу: старые первыми
        SET @rows = @@ROWCOUNT;
        IF @rows = 0 BREAK;

        BEGIN TRANSACTION;                                        -- короткая транзакция на батч
        DELETE r FROM ops.RejectedEvent AS r JOIN @ids AS i ON i.InboxId = r.InboxId;
        SET @deletedRejected += @@ROWCOUNT;
        DELETE w FROM ops.WebhookInbox AS w JOIN @ids AS i ON i.InboxId = w.InboxId;
        SET @deletedInbox += @@ROWCOUNT;
        COMMIT;

        SET @batch += 1;
        WAITFOR DELAY @pause;                                     -- пауза: дать OLTP и репликации дышать
    END;

    SELECT @batch AS batches, @deletedInbox AS deleted_inbox, @deletedRejected AS deleted_rejected,
           IIF(@batch >= @MaxBatches, 'limit reached: run again', 'done') AS state;
END;
GO

-- Батчевое обновление: пересчёт LastEventAt по событиям (например, после массовой загрузки) блоками по ShipmentId
CREATE OR ALTER PROCEDURE ship.usp_RecomputeLastEventAt
    @BatchSize int = 10000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @from bigint = 0, @maxId bigint = (SELECT MAX(ShipmentId) FROM ship.Shipment), @updated int = 0;
    WHILE @from < @maxId
    BEGIN
        -- Выравнивание отправления по последнему событию: LastEventAt, StatusId, DeliveredAt — то, что ingest делает на лету,
        -- а для данных, загруженных мимо него (seed, генераторы, восстановление), делается пакетно
        UPDATE s SET LastEventAt = e.OccurredAt, StatusId = e.StatusId,
                     DeliveredAt = CASE WHEN e.StatusId = 7 THEN e.OccurredAt ELSE s.DeliveredAt END,
                     UpdatedAt = SYSUTCDATETIME(), ModifiedBy = 'recompute'
        FROM ship.Shipment AS s
        CROSS APPLY (SELECT TOP (1) t.StatusId, t.OccurredAt FROM ship.TrackingEvent AS t
                     WHERE t.ShipmentId = s.ShipmentId ORDER BY t.OccurredAt DESC, t.EventId DESC) AS e
        WHERE s.ShipmentId > @from AND s.ShipmentId <= @from + @BatchSize
          AND (s.LastEventAt IS DISTINCT FROM e.OccurredAt OR s.StatusId <> e.StatusId);      -- только реально изменившиеся: меньше журнала и версий
        SET @updated += @@ROWCOUNT;
        SET @from += @BatchSize;
    END;
    SELECT @updated AS updated_rows;
END;
GO

-- diagnostic: safe to re-run (на пустом inbox — ноль батчей)
EXEC ops.usp_PurgeInbox @OlderThanDays = 3650, @BatchSize = 1000, @MaxBatches = 1;   -- ничего старше 10 лет нет: проверка пути без удаления
SELECT total_log_size_mb, active_log_size_mb, log_truncation_holdup_reason, log_since_last_log_backup_mb
FROM sys.dm_db_log_stats(DB_ID());
GO
