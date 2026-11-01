-- diagnostic: safe to re-run
/*
  040_deadlock_demo.sql — deadlock: сценарий для двух сессий (в комментариях), чтение графов из system_health, retry-обёртка (урок 8.5).
  Сам deadlock нельзя воспроизвести в одной сессии; блоки ниже читают историю и показывают шаблон повтора.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

/* Сценарий для двух окон (выполнить вручную):
   -- Сессия 1
   BEGIN TRANSACTION;
   UPDATE ship.Shipment SET UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = 1;
   WAITFOR DELAY '00:00:05';
   UPDATE ship.Shipment SET UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = 2;
   ROLLBACK;
   -- Сессия 2 (в течение 5 секунд)
   BEGIN TRANSACTION;
   UPDATE ship.Shipment SET UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = 2;
   UPDATE ship.Shipment SET UpdatedAt = SYSUTCDATETIME() WHERE ShipmentId = 1;
   ROLLBACK;
*/

-- 1. Графы из кольцевого буфера system_health
WITH xe AS
(
    SELECT CAST(target_data AS xml) AS x
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
    WHERE s.name = N'system_health' AND t.target_name = N'ring_buffer'
)
SELECT ev.value('@timestamp', 'datetime2(3)') AS occurred_at, ev.query('data/value/deadlock') AS deadlock_graph
FROM xe
CROSS APPLY x.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS q(ev)
ORDER BY occurred_at DESC;

-- 2. Графы из файловой цели (история дольше)
SELECT TOP (20) CAST(event_data AS xml).value('(event/@timestamp)[1]', 'datetime2(3)') AS occurred_at,
       CAST(event_data AS xml).query('event/data/value/deadlock') AS deadlock_graph
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
WHERE object_name = N'xml_deadlock_report'
ORDER BY occurred_at DESC;

-- 3. Счётчик deadlock-ов с момента старта
SELECT cntr_value AS deadlocks_total FROM sys.dm_os_performance_counters
WHERE counter_name = N'Number of Deadlocks/sec' AND instance_name = N'_Total';
GO

-- 4. Retry-обёртка для T-SQL (Agent, скрипты); в приложении — SqlRetryLogic (глава 12)
DECLARE @batch ops.tt_TrackingEventIn;
INSERT INTO @batch VALUES ('FX0000000001', 'retry-demo-1', 'AT_HUB', '2026-09-02T05:00:00', N'Москва', '127018', NULL, NULL);

DECLARE @attempt int = 0, @maxAttempts int = 3;
BEGIN TRANSACTION;   -- демонстрация в транзакции с откатом
WHILE @attempt < @maxAttempts
BEGIN
    BEGIN TRY
        SET @attempt += 1;
        EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'FASTEX', @Events = @batch;
        PRINT CONCAT('ok on attempt ', @attempt);
        BREAK;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205 AND @attempt < @maxAttempts
        BEGIN
            DECLARE @delay char(12) = CONCAT('00:00:00.', RIGHT(CONCAT('000', 100 * @attempt + ABS(CHECKSUM(NEWID())) % 100), 3));
            PRINT CONCAT('deadlock, retry after ', @delay);
            WAITFOR DELAY @delay;
        END
        ELSE THROW;
    END CATCH;
END;
ROLLBACK;
GO
