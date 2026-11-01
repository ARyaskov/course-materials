/* 13-async/010_outbox_queue.sql
   Очередь outbox для нескольких воркеров: партиционированный dequeue (события одного агрегата — у одного воркера),
   возврат poison-записей после разбора, статистика по воркерам. Идемпотентен.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Партиция агрегата — вычисляемый столбец в ключе индекса очереди: предикат по партиции становится частью seek-а
IF COL_LENGTH(N'ops.Outbox', N'Partition') IS NULL
    ALTER TABLE ops.Outbox ADD Partition AS CAST(AggregateId % 16 AS tinyint) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Outbox_Pending_Partition' AND object_id = OBJECT_ID(N'ops.Outbox'))
    CREATE INDEX IX_Outbox_Pending_Partition ON ops.Outbox (Partition, CreatedAt, OutboxId)
        INCLUDE (Topic, LockedUntil, Attempts)
        WHERE ProcessedAt IS NULL;
GO

-- Dequeue с партициями: воркер k из N берёт только записи с Partition % N = k (N делит 16: 1, 2, 4, 8, 16)
CREATE OR ALTER PROCEDURE ops.usp_DequeueOutbox
    @BatchSize      int = 50,
    @LeaseSeconds   int = 60,
    @WorkerId       nvarchar(64),
    @MaxAttempts    tinyint = 10,
    @PartitionCount tinyint = NULL,     -- NULL: без партиционирования (поведение главы 8)
    @Partition      tinyint = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now datetime2(3) = SYSUTCDATETIME();

    IF @PartitionCount IS NOT NULL AND (16 % @PartitionCount <> 0 OR @Partition IS NULL OR @Partition >= @PartitionCount)
        THROW 50081, N'PartitionCount должен делить 16, Partition — в диапазоне [0, PartitionCount)', 1;

    ;WITH next AS
    (
        SELECT TOP (@BatchSize) o.OutboxId, o.LockedUntil, o.LockedBy, o.Attempts, o.Topic, o.AggregateType, o.AggregateId, o.Payload   -- OUTPUT через CTE видит только столбцы CTE
        FROM ops.Outbox AS o WITH (READPAST, UPDLOCK, ROWLOCK)
        WHERE o.ProcessedAt IS NULL
          AND (o.LockedUntil IS NULL OR o.LockedUntil < @now)
          AND o.Attempts < @MaxAttempts
          AND (@PartitionCount IS NULL OR o.Partition % @PartitionCount = @Partition)
        ORDER BY o.CreatedAt, o.OutboxId
    )
    UPDATE next
    SET LockedUntil = DATEADD(SECOND, @LeaseSeconds, @now), LockedBy = @WorkerId, Attempts = Attempts + 1
    OUTPUT inserted.OutboxId, inserted.Topic, inserted.AggregateType, inserted.AggregateId, inserted.Payload, inserted.Attempts, inserted.LockedUntil;
END;
GO

-- Poison → обратно в очередь после разбора (сброс попыток, пометка в LastError)
CREATE OR ALTER PROCEDURE ops.usp_RequeueOutbox
    @OutboxId bigint,
    @Reason   nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ops.Outbox
    SET Attempts = 0, LockedUntil = NULL, LockedBy = NULL,
        LastError = CONCAT(N'requeued ', CONVERT(varchar(30), SYSUTCDATETIME(), 126), N' by ', ORIGINAL_LOGIN(), N': ', @Reason)
    WHERE OutboxId = @OutboxId AND ProcessedAt IS NULL;
    IF @@ROWCOUNT = 0 THROW 50001, N'Запись outbox не найдена или уже обработана', 1;
END;
GO

-- Кто что держит: активные аренды по воркерам
CREATE OR ALTER VIEW ops.vw_OutboxWorkers
AS
SELECT LockedBy AS WorkerId, COUNT(*) AS leased, MIN(LockedUntil) AS earliest_lease_end, MAX(Attempts) AS max_attempts
FROM ops.Outbox
WHERE ProcessedAt IS NULL AND LockedUntil >= SYSUTCDATETIME()
GROUP BY LockedBy;
GO

-- diagnostic: safe to re-run
BEGIN TRANSACTION;
INSERT INTO ops.Outbox (Topic, AggregateType, AggregateId, Payload)
SELECT 'test.partitioned', 'Shipment', v.value, JSON_OBJECT('n': v.value) FROM GENERATE_SERIES(1, 32) AS v;

DECLARE @a TABLE (OutboxId bigint, Topic varchar(64), AggregateType varchar(32), AggregateId bigint, Payload json, Attempts tinyint, LockedUntil datetime2(3));
DECLARE @b TABLE (OutboxId bigint, Topic varchar(64), AggregateType varchar(32), AggregateId bigint, Payload json, Attempts tinyint, LockedUntil datetime2(3));
INSERT INTO @a EXEC ops.usp_DequeueOutbox @BatchSize = 100, @LeaseSeconds = 30, @WorkerId = N'w0', @PartitionCount = 2, @Partition = 0;
INSERT INTO @b EXEC ops.usp_DequeueOutbox @BatchSize = 100, @LeaseSeconds = 30, @WorkerId = N'w1', @PartitionCount = 2, @Partition = 1;
SELECT 'w0' AS worker, COUNT(*) AS taken, MIN(AggregateId % 2) AS min_parity, MAX(AggregateId % 2) AS max_parity FROM @a
UNION ALL
SELECT 'w1', COUNT(*), MIN(AggregateId % 2), MAX(AggregateId % 2) FROM @b;   -- чётные у w0, нечётные у w1, наборы не пересекаются
SELECT * FROM ops.vw_OutboxWorkers;
ROLLBACK;
GO
