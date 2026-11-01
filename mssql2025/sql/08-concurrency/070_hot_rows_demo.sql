-- diagnostic: safe to re-run
/*
  070_hot_rows_demo.sql — «горячие строки» при ingest (урок 8.10): один пакет на одно отправление из нескольких сессий.
  Однопоточная часть — здесь (в транзакции с откатом); многопоточная — через scripts/hot-rows.ps1 (N параллельных вызовов).
  Показывает: ожидания LCK_M_* и XACT, отсутствие эскалации, число событий после конкурентных вставок.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Снимок ожиданий до нагрузки
DROP TABLE IF EXISTS #waits_before;
SELECT wait_type, waiting_tasks_count, wait_time_ms INTO #waits_before FROM sys.dm_os_wait_stats WHERE wait_type LIKE N'LCK_M_%' OR wait_type = N'PAGELATCH_EX';

-- 2. Пакет из 200 событий на одно отправление (дубли и новые вперемешку), два вызова подряд
BEGIN TRANSACTION;
DECLARE @batch ops.tt_TrackingEventIn;
INSERT INTO @batch (TrackingNumber, ExternalEventId, ExternalStatus, OccurredAt, LocationText, LocationPostalCode, Description, RawFragment)
SELECT 'FX0000000001', CONCAT('hot-', v.value), CHOOSE(1 + v.value % 4, 'IN_TRANSIT', 'AT_HUB', 'OUT_FOR_DELIVERY', 'IN_TRANSIT'),
       DATEADD(MINUTE, v.value, '2026-09-02T05:00:00'), N'Москва', '127018', NULL, NULL
FROM GENERATE_SERIES(1, 200) AS v;

EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'FASTEX', @Events = @batch;   -- 200 новых
EXEC ops.usp_IngestTrackingEvents @CarrierCode = 'FASTEX', @Events = @batch;   -- 0 новых, 200 дублей

SELECT resource_type, request_mode, COUNT(*) AS locks
FROM sys.dm_tran_locks WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode ORDER BY resource_type;                    -- XACT/OBJECT, без KEY-массива
ROLLBACK;

-- 3. Разница ожиданий
SELECT a.wait_type, a.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS tasks, a.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS ms
FROM sys.dm_os_wait_stats AS a LEFT JOIN #waits_before AS b ON b.wait_type = a.wait_type
WHERE (a.wait_type LIKE N'LCK_M_%' OR a.wait_type = N'PAGELATCH_EX') AND a.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) > 0;
DROP TABLE IF EXISTS #waits_before;
GO
