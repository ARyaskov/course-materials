-- diagnostic: safe to re-run
/*
  040_new_functions.sql — новые функции T-SQL 2022–2025 (урок 2.3):
  0) проверка доступности функций на стенде;
  1) события по 6-часовым бакетам с пустыми бакетами;
  2) рассинхрон DeliveredAt с событиями через IS DISTINCT FROM;
  3) CONCAT_WS против ||.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 0. Доступность функций
DECLARE @checks TABLE (feature sysname, sql nvarchar(400));
INSERT INTO @checks VALUES
    (N'CURRENT_DATE',     N'SELECT CURRENT_DATE'),
    (N'||',               N'SELECT ''a'' || ''b'''),
    (N'UNISTR',           N'SELECT UNISTR(N''\0041'')'),
    (N'BASE64_ENCODE',    N'SELECT BASE64_ENCODE(0x41)'),
    (N'PRODUCT',          N'SELECT PRODUCT(v) FROM (VALUES (2.0), (3.0)) AS t(v)'),
    (N'REGEXP_LIKE',      N'SELECT IIF(REGEXP_LIKE(''FX001'', ''^FX[0-9]+$''), 1, 0)'),
    (N'DATE_BUCKET',      N'SELECT DATE_BUCKET(DAY, 7, SYSDATETIME())'),
    (N'IS DISTINCT FROM', N'SELECT IIF(1 IS DISTINCT FROM NULL, 1, 0)'),
    (N'JSON_ARRAYAGG',    N'SELECT JSON_ARRAYAGG(v) FROM (VALUES (1), (2)) AS t(v)'),
    (N'json type',        N'DECLARE @j json = ''{"a":1}''; SELECT @j');

DECLARE @feature sysname, @sql nvarchar(400);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT feature, sql FROM @checks;
OPEN cur; FETCH NEXT FROM cur INTO @feature, @sql;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
        PRINT CONCAT(@feature, ': ok');
    END TRY
    BEGIN CATCH
        PRINT CONCAT(@feature, ': ', ERROR_NUMBER(), ' ', ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM cur INTO @feature, @sql;
END;
CLOSE cur; DEALLOCATE cur;
GO

-- 1. События по 6-часовым бакетам за 7 дней, включая пустые
DECLARE @from datetime2(3) = '2026-09-08', @to datetime2(3) = '2026-09-15';
SELECT DATEADD(HOUR, 6 * b.value, @from) AS bucket_start, COUNT(t.EventId) AS events
FROM GENERATE_SERIES(0, DATEDIFF(HOUR, @from, @to) / 6 - 1) AS b
LEFT JOIN demo.TrackingEvent AS t
       ON t.OccurredAt >= DATEADD(HOUR, 6 * b.value, @from)
      AND t.OccurredAt <  DATEADD(HOUR, 6 * (b.value + 1), @from)
GROUP BY b.value
ORDER BY bucket_start;
GO

-- 2. DeliveredAt отличается от времени события DELIVERED (NULL-безопасно)
SELECT s.ShipmentId, s.DeliveredAt, d.OccurredAt AS delivered_event_at
FROM demo.Shipment AS s
OUTER APPLY (SELECT TOP (1) t.OccurredAt FROM demo.TrackingEvent AS t
             WHERE t.ShipmentId = s.ShipmentId AND t.Status = 'DELIVERED' ORDER BY t.OccurredAt DESC) AS d
WHERE s.DeliveredAt IS DISTINCT FROM d.OccurredAt;
GO

-- 3. CONCAT_WS против ||
SELECT TOP (5) s.TrackingNumber,
       CONCAT_WS(' / ', s.City, s.Status, CONVERT(varchar(19), s.DeliveredAt, 120)) AS concat_ws_result,   -- NULL пропущен
       s.City || ' / ' || s.Status || ' / ' || CONVERT(varchar(19), s.DeliveredAt, 120)  AS pipe_result        -- NULL, если DeliveredAt NULL
FROM demo.Shipment AS s
WHERE s.DeliveredAt IS NULL;
GO
