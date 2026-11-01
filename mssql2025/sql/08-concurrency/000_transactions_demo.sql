-- diagnostic: safe to re-run
/*
  000_transactions_demo.sql — @@TRANCOUNT, вложенные COMMIT/ROLLBACK, SAVE TRANSACTION, обречённая транзакция при ошибке в процедуре (урок 8.1).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Счётчик транзакций: внутренний COMMIT ничего не фиксирует, внешний ROLLBACK откатывает всё
BEGIN TRANSACTION;                 PRINT CONCAT('после BEGIN #1: ', @@TRANCOUNT);
    BEGIN TRANSACTION;             PRINT CONCAT('после BEGIN #2: ', @@TRANCOUNT);
        INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
    COMMIT;                        PRINT CONCAT('после COMMIT #2: ', @@TRANCOUNT);
ROLLBACK;                          PRINT CONCAT('после ROLLBACK: ', @@TRANCOUNT);
SELECT COUNT(*) AS rows_inserted_in_last_5s FROM demo.Ping WHERE At > DATEADD(SECOND, -5, SYSUTCDATETIME());   -- 0
GO

-- 2. Точка сохранения: частичный откат
BEGIN TRANSACTION;
INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
SAVE TRANSACTION before_risky;
INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
ROLLBACK TRANSACTION before_risky;
PRINT CONCAT('после ROLLBACK TO savepoint: @@TRANCOUNT = ', @@TRANCOUNT);   -- 1
ROLLBACK;                          -- демонстрация: не оставляем следов
GO

-- 3. Ошибка в процедуре внутри внешней транзакции: обречена, откат — у вызывающего
SET XACT_ABORT ON;
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @empty ops.tt_TrackingEventIn;
    EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'NO-SUCH-CARRIER', @Events = @empty;
END TRY
BEGIN CATCH
    PRINT CONCAT('ошибка ', ERROR_NUMBER(), '; @@TRANCOUNT = ', @@TRANCOUNT, '; XACT_STATE() = ', XACT_STATE());
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH;
GO

-- 4. Режим и уровень изоляции сессии
SELECT IIF(@@OPTIONS & 2 = 2, 'implicit', 'autocommit') AS transaction_mode,
       CASE transaction_isolation_level WHEN 1 THEN 'ReadUncommitted' WHEN 2 THEN 'ReadCommitted' WHEN 3 THEN 'RepeatableRead' WHEN 4 THEN 'Serializable' WHEN 5 THEN 'Snapshot' END AS isolation
FROM sys.dm_exec_sessions WHERE session_id = @@SPID;
GO
