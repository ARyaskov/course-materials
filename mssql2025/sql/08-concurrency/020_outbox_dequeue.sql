/*
  020_outbox_dequeue.sql — очередь на таблице ops.Outbox (урок 8.6). Идемпотентен.
  LockedBy — кто арендовал; usp_DequeueOutbox (READPAST, UPDLOCK, ROWLOCK + OUTPUT), usp_CompleteOutbox, usp_FailOutbox, отчёт poison.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'ops.Outbox', N'LockedBy') IS NULL
    ALTER TABLE ops.Outbox ADD LockedBy nvarchar(64) NULL;
GO

CREATE OR ALTER PROCEDURE ops.usp_DequeueOutbox
    @BatchSize    int = 50,
    @LeaseSeconds int = 60,
    @WorkerId     nvarchar(64),
    @MaxAttempts  tinyint = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @now datetime2(3) = SYSUTCDATETIME();

    ;WITH next AS
    (
        SELECT TOP (@BatchSize) o.OutboxId, o.LockedUntil, o.LockedBy, o.Attempts, o.Topic, o.AggregateType, o.AggregateId, o.Payload   -- OUTPUT через CTE видит только столбцы CTE
        FROM ops.Outbox AS o WITH (READPAST, UPDLOCK, ROWLOCK)
        WHERE o.ProcessedAt IS NULL
          AND (o.LockedUntil IS NULL OR o.LockedUntil < @now)
          AND o.Attempts < @MaxAttempts
        ORDER BY o.CreatedAt, o.OutboxId
    )
    UPDATE next
    SET LockedUntil = DATEADD(SECOND, @LeaseSeconds, @now), LockedBy = @WorkerId, Attempts = Attempts + 1
    OUTPUT inserted.OutboxId, inserted.Topic, inserted.AggregateType, inserted.AggregateId, inserted.Payload, inserted.Attempts, inserted.LockedUntil;
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_CompleteOutbox
    @Ids      ops.tt_IdList READONLY,
    @WorkerId nvarchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE o SET ProcessedAt = SYSUTCDATETIME(), LockedUntil = NULL, LastError = NULL
    FROM ops.Outbox AS o JOIN @Ids AS i ON i.Id = o.OutboxId
    WHERE o.LockedBy = @WorkerId AND o.ProcessedAt IS NULL;
    SELECT @@ROWCOUNT AS completed;
END;
GO

CREATE OR ALTER PROCEDURE ops.usp_FailOutbox
    @OutboxId bigint,
    @WorkerId nvarchar(64),
    @Error    nvarchar(1000)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE ops.Outbox
    SET LastError = @Error, LockedUntil = DATEADD(SECOND, 30 * Attempts, SYSUTCDATETIME())   -- backoff по числу попыток
    WHERE OutboxId = @OutboxId AND LockedBy = @WorkerId AND ProcessedAt IS NULL;
END;
GO

CREATE OR ALTER VIEW ops.vw_OutboxPoison
AS
SELECT OutboxId, Topic, AggregateType, AggregateId, Attempts, LastError, CreatedAt, LockedBy
FROM ops.Outbox
WHERE ProcessedAt IS NULL AND Attempts >= 10;
GO

-- Проверка в транзакции с откатом: 20 записей, два воркера, аренда, завершение
BEGIN TRANSACTION;
INSERT INTO ops.Outbox (Topic, AggregateType, AggregateId, Payload)
SELECT 'test.topic', 'Test', v.value, JSON_OBJECT('n': v.value) FROM GENERATE_SERIES(1, 20) AS v;

DECLARE @taken TABLE (OutboxId bigint, Topic varchar(64), AggregateType varchar(32), AggregateId bigint, Payload json, Attempts tinyint, LockedUntil datetime2(3));
INSERT INTO @taken EXEC ops.usp_DequeueOutbox @BatchSize = 5, @LeaseSeconds = 60, @WorkerId = N'worker-A';
INSERT INTO @taken EXEC ops.usp_DequeueOutbox @BatchSize = 5, @LeaseSeconds = 60, @WorkerId = N'worker-B';   -- следующие 5: READPAST не нужен внутри одной сессии, но аренда уже стоит
SELECT OutboxId, Attempts, LockedUntil FROM @taken ORDER BY OutboxId;   -- 10 разных записей

DECLARE @done ops.tt_IdList;
INSERT INTO @done SELECT TOP (3) OutboxId FROM @taken ORDER BY OutboxId;
EXEC ops.usp_CompleteOutbox @Ids = @done, @WorkerId = N'worker-A';      -- completed = 3 (только записи worker-A)
EXEC ops.usp_FailOutbox @OutboxId = 4, @WorkerId = N'worker-A', @Error = N'HTTP 503';
SELECT OutboxId, ProcessedAt, LockedBy, Attempts, LastError, LockedUntil FROM ops.Outbox WHERE Topic = 'test.topic' ORDER BY OutboxId;
ROLLBACK;
GO
