/* 09-performance/025_wait_stats.sql
   Снимки sys.dm_os_wait_stats до/после нагрузки и разность между ними; ожидания текущей сессии. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.WaitStatsSnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE ops.WaitStatsSnapshot
    (
        SnapshotId        int           NOT NULL,
        Label             nvarchar(100) NOT NULL,
        TakenAt           datetime2(3)  NOT NULL,
        WaitType          nvarchar(60)  NOT NULL,
        WaitingTasks      bigint        NOT NULL,
        WaitTimeMs        bigint        NOT NULL,
        SignalWaitTimeMs  bigint        NOT NULL,
        MaxWaitTimeMs     bigint        NOT NULL,
        CONSTRAINT PK_WaitStatsSnapshot PRIMARY KEY CLUSTERED (SnapshotId, WaitType)
    );
END;
GO

-- Ожидания, которые не означают проблему: фоновые задачи, таймеры, простаивающие потоки
CREATE OR ALTER FUNCTION ops.tvf_BenignWaits ()
RETURNS TABLE
AS
RETURN
    SELECT v.WaitType
    FROM (VALUES
        (N'BROKER_EVENTHANDLER'), (N'BROKER_RECEIVE_WAITFOR'), (N'BROKER_TASK_STOP'), (N'BROKER_TO_FLUSH'), (N'BROKER_TRANSMITTER'),
        (N'CHECKPOINT_QUEUE'), (N'CHKPT'), (N'CLR_AUTO_EVENT'), (N'CLR_MANUAL_EVENT'), (N'CLR_SEMAPHORE'),
        (N'DBMIRROR_DBM_EVENT'), (N'DBMIRROR_EVENTS_QUEUE'), (N'DBMIRROR_WORKER_QUEUE'), (N'DBMIRRORING_CMD'),
        (N'DIRTY_PAGE_POLL'), (N'DISPATCHER_QUEUE_SEMAPHORE'), (N'EXECSYNC'), (N'FSAGENT'), (N'FT_IFTS_SCHEDULER_IDLE_WAIT'), (N'FT_IFTSHC_MUTEX'),
        (N'HADR_CLUSAPI_CALL'), (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'), (N'HADR_LOGCAPTURE_WAIT'), (N'HADR_NOTIFICATION_DEQUEUE'),
        (N'HADR_TIMER_TASK'), (N'HADR_WORK_QUEUE'), (N'KSOURCE_WAKEUP'), (N'LAZYWRITER_SLEEP'), (N'LOGMGR_QUEUE'),
        (N'MEMORY_ALLOCATION_EXT'), (N'ONDEMAND_TASK_QUEUE'), (N'PARALLEL_REDO_DRAIN_WORKER'), (N'PARALLEL_REDO_LOG_CACHE'),
        (N'PARALLEL_REDO_TRAN_LIST'), (N'PARALLEL_REDO_WORKER_SYNC'), (N'PARALLEL_REDO_WORKER_WAIT_WORK'), (N'PREEMPTIVE_OS_FLUSHFILEBUFFERS'),
        (N'PREEMPTIVE_XE_GETTARGETSTATE'), (N'PVS_PREALLOCATE'), (N'PWAIT_ALL_COMPONENTS_INITIALIZED'), (N'PWAIT_DIRECTLOGCONSUMER_GETNEXT'),
        (N'PWAIT_EXTENSIBILITY_CLEANUP_TASK'), (N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'), (N'QDS_ASYNC_QUEUE'), (N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'),
        (N'QDS_SHUTDOWN_QUEUE'), (N'REDO_THREAD_PENDING_WORK'), (N'REQUEST_FOR_DEADLOCK_SEARCH'), (N'RESOURCE_QUEUE'), (N'SERVER_IDLE_CHECK'),
        (N'SLEEP_BPOOL_FLUSH'), (N'SLEEP_DBSTARTUP'), (N'SLEEP_DCOMSTARTUP'), (N'SLEEP_MASTERDBREADY'), (N'SLEEP_MASTERMDREADY'),
        (N'SLEEP_MASTERUPGRADED'), (N'SLEEP_MSDBSTARTUP'), (N'SLEEP_SYSTEMTASK'), (N'SLEEP_TASK'), (N'SLEEP_TEMPDBSTARTUP'),
        (N'SNI_HTTP_ACCEPT'), (N'SOS_WORK_DISPATCHER'), (N'SP_SERVER_DIAGNOSTICS_SLEEP'), (N'SQLTRACE_BUFFER_FLUSH'), (N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
        (N'SQLTRACE_WAIT_ENTRIES'), (N'VDILOGWRITER_WAIT'), (N'WAIT_FOR_RESULTS'), (N'WAITFOR'), (N'WAITFOR_TASKSHUTDOWN'), (N'WAIT_XTP_RECOVERY'),
        (N'WAIT_XTP_HOST_WAIT'), (N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG'), (N'WAIT_XTP_CKPT_CLOSE'), (N'XE_DISPATCHER_JOIN'), (N'XE_DISPATCHER_WAIT'),
        (N'XE_TIMER_EVENT'), (N'XE_LIVE_TARGET_TVF'), (N'STARTUP_DEPENDENCY_MANAGER'), (N'SOS_WORKER_MIGRATION')
    ) AS v (WaitType);
GO

CREATE OR ALTER PROCEDURE ops.usp_SnapshotWaitStats
    @Label      nvarchar(100),
    @SnapshotId int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @SnapshotId = ISNULL((SELECT MAX(SnapshotId) FROM ops.WaitStatsSnapshot), 0) + 1;
    INSERT INTO ops.WaitStatsSnapshot (SnapshotId, Label, TakenAt, WaitType, WaitingTasks, WaitTimeMs, SignalWaitTimeMs, MaxWaitTimeMs)
    SELECT @SnapshotId, @Label, SYSUTCDATETIME(), wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms, max_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type COLLATE DATABASE_DEFAULT NOT IN (SELECT WaitType FROM ops.tvf_BenignWaits())   -- DMV: коллация экземпляра;
END;
GO

-- Разность двух снимков: что добавила нагрузка между ними
CREATE OR ALTER FUNCTION ops.tvf_WaitStatsDiff (@FromSnapshotId int, @ToSnapshotId int)
RETURNS TABLE
AS
RETURN
    SELECT TOP (25)
           b.WaitType,
           b.WaitingTasks - ISNULL(a.WaitingTasks, 0)                            AS waits,
           b.WaitTimeMs - ISNULL(a.WaitTimeMs, 0)                                AS wait_ms,
           b.SignalWaitTimeMs - ISNULL(a.SignalWaitTimeMs, 0)                    AS signal_ms,       -- время в очереди за CPU после сигнала
           CAST((b.WaitTimeMs - ISNULL(a.WaitTimeMs, 0)) * 1.0
                / NULLIF(b.WaitingTasks - ISNULL(a.WaitingTasks, 0), 0) AS decimal(12, 2))          AS avg_wait_ms,
           CAST(100.0 * (b.WaitTimeMs - ISNULL(a.WaitTimeMs, 0))
                / NULLIF(SUM(b.WaitTimeMs - ISNULL(a.WaitTimeMs, 0)) OVER (), 0) AS decimal(5, 1))  AS pct
    FROM ops.WaitStatsSnapshot AS b
    LEFT JOIN ops.WaitStatsSnapshot AS a ON a.SnapshotId = @FromSnapshotId AND a.WaitType = b.WaitType
    WHERE b.SnapshotId = @ToSnapshotId
      AND b.WaitTimeMs - ISNULL(a.WaitTimeMs, 0) > 0
    ORDER BY wait_ms DESC;
GO

-- diagnostic: safe to re-run
-- Ожидания с момента старта экземпляра (или последнего сброса), топ-15
SELECT TOP (15) wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms,
       CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS decimal(5, 1)) AS pct
FROM sys.dm_os_wait_stats
WHERE wait_type COLLATE DATABASE_DEFAULT NOT IN (SELECT WaitType FROM ops.tvf_BenignWaits())   -- DMV: коллация экземпляра AND wait_time_ms > 0
ORDER BY wait_time_ms DESC;

-- Ожидания текущей сессии: обнуляются при повторном использовании соединения из пула
SELECT wait_type, waiting_tasks_count, wait_time_ms FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID ORDER BY wait_time_ms DESC;

-- Проба: снимок → нагрузка → снимок → разность
DECLARE @s1 int, @s2 int;
EXEC ops.usp_SnapshotWaitStats @Label = N'probe: before', @SnapshotId = @s1 OUTPUT;
SELECT COUNT_BIG(*) AS events FROM ship.TrackingEvent AS e JOIN ship.Shipment AS s ON s.ShipmentId = e.ShipmentId WHERE s.StatusId = 7;
EXEC ops.usp_SnapshotWaitStats @Label = N'probe: after', @SnapshotId = @s2 OUTPUT;
SELECT * FROM ops.tvf_WaitStatsDiff(@s1, @s2);
DELETE FROM ops.WaitStatsSnapshot WHERE SnapshotId IN (@s1, @s2);
GO
