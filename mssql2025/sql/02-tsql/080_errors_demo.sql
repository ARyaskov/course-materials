/*
  080_errors_demo.sql — XACT_ABORT, TRY/CATCH, XACT_STATE, журнал ошибок, шаблон процедуры (урок 2.7).
  Создаёт demo.ErrorLog, demo.usp_LogError, demo.usp_MarkDelivered (идемпотентно); демонстрации откатываются.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'demo.ErrorLog', N'U') IS NULL
CREATE TABLE demo.ErrorLog
(
    ErrorLogId    bigint         NOT NULL IDENTITY PRIMARY KEY,
    LoggedAt      datetime2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    ErrorNumber   int            NOT NULL,
    Severity      tinyint        NOT NULL,
    State         tinyint        NOT NULL,
    ProcedureName sysname        NULL,
    LineNumber    int            NULL,
    Message       nvarchar(2048) NOT NULL,
    Context       nvarchar(max)  NULL,
    SessionUser   sysname        NOT NULL DEFAULT ORIGINAL_LOGIN(),
    HostName      sysname        NULL DEFAULT HOST_NAME()
);
GO

CREATE OR ALTER PROCEDURE demo.usp_LogError
    @Context nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF ERROR_NUMBER() IS NULL RETURN;
    IF XACT_STATE() = -1 RETURN;
    INSERT INTO demo.ErrorLog (ErrorNumber, Severity, State, ProcedureName, LineNumber, Message, Context)
    VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE(), @Context);
END;
GO

CREATE OR ALTER PROCEDURE demo.usp_MarkDelivered
    @TrackingNumber varchar(64),
    @DeliveredAt    datetime2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ownTran bit = IIF(@@TRANCOUNT = 0, 1, 0);

    BEGIN TRY
        IF @ownTran = 1 BEGIN TRANSACTION;

        UPDATE demo.Shipment
        SET Status = 'DELIVERED', DeliveredAt = @DeliveredAt
        WHERE TrackingNumber = @TrackingNumber;

        IF @@ROWCOUNT = 0
        BEGIN
            DECLARE @msg nvarchar(200) = FORMATMESSAGE(N'Отправление %s не найдено', @TrackingNumber);
            THROW 50001, @msg, 1;
        END;

        INSERT INTO demo.TrackingEvent (ShipmentId, Status, OccurredAt)
        SELECT ShipmentId, 'DELIVERED', @DeliveredAt FROM demo.Shipment WHERE TrackingNumber = @TrackingNumber;

        IF @ownTran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF @ownTran = 1 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        IF @ownTran = 1
            EXEC demo.usp_LogError @Context = @TrackingNumber;
        THROW;
    END CATCH;
END;
GO

-- Сценарий 1: XACT_ABORT OFF — половинный коммит (внутри внешней транзакции, чтобы откатить демонстрацию)
BEGIN TRANSACTION demo_outer;
SAVE TRANSACTION before_demo;
SET XACT_ABORT OFF;
DECLARE @before int = (SELECT COUNT(*) FROM demo.Ping);
BEGIN TRY
    INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
    INSERT INTO demo.TrackingEvent (ShipmentId, Status, OccurredAt) VALUES (999999999, 'X', SYSUTCDATETIME());
END TRY
BEGIN CATCH
    PRINT CONCAT('сценарий 1: ошибка ', ERROR_NUMBER(), ' перехвачена, транзакция жива: XACT_STATE() = ', XACT_STATE());
END CATCH;
INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
DECLARE @after1 int = (SELECT COUNT(*) FROM demo.Ping);
PRINT CONCAT('сценарий 1: строк в demo.Ping добавлено ', @after1 - @before, ' (ожидаем 2 — половинный результат)');
ROLLBACK TRANSACTION before_demo;
COMMIT;
GO

-- Сценарий 2: XACT_ABORT ON с TRY/CATCH — обречённая транзакция, откат, лог
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO demo.Ping (At) VALUES (SYSUTCDATETIME());
    INSERT INTO demo.TrackingEvent (ShipmentId, Status, OccurredAt) VALUES (999999999, 'X', SYSUTCDATETIME());
    COMMIT;
END TRY
BEGIN CATCH
    PRINT CONCAT('сценарий 2: XACT_STATE() = ', XACT_STATE(), ' (ожидаем -1)');
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    EXEC demo.usp_LogError @Context = N'{"scenario":2}';
END CATCH;
SELECT TOP (1) ErrorNumber, Message, Context FROM demo.ErrorLog ORDER BY ErrorLogId DESC;
GO

-- Сценарий 3: вызов процедуры с ошибкой изнутри внешней транзакции — процедура не откатывает, откат делает вызывающий
BEGIN TRANSACTION;
BEGIN TRY
    EXEC demo.usp_MarkDelivered @TrackingNumber = 'NO-SUCH-TRACKING', @DeliveredAt = '2026-09-16T10:00:00';
END TRY
BEGIN CATCH
    PRINT CONCAT('сценарий 3: ', ERROR_MESSAGE(), '; @@TRANCOUNT = ', @@TRANCOUNT, ' (ожидаем 1 — процедура не откатывала); XACT_STATE() = ', XACT_STATE(), ' (ожидаем -1 — обречена THROW под XACT_ABORT)');
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
END CATCH;
GO
