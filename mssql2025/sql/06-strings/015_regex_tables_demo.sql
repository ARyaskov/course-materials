-- diagnostic: safe to re-run
/*
  015_regex_tables_demo.sql — REGEXP_MATCHES и REGEXP_SPLIT_TO_TABLE (урок 6.3).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Разбор описаний неудачных попыток доставки (табличная переменная — вместо вставки в demo)
DECLARE @notes TABLE (EventId int IDENTITY, Description nvarchar(200));
INSERT INTO @notes (Description) VALUES
    (N'Попытка 1 из 3 неудачна: получатель отсутствует; далее 2026-09-03 10:00-14:00'),
    (N'Попытка 2 из 3 неудачна: адрес не найден; далее 2026-09-04 09:00-12:00'),
    (N'Попытка 3 из 3 неудачна: получатель отказался; далее 2026-09-05 14:00-18:00'),
    (N'Доставлено, получатель А. Иванова'),
    (N'Попытка 1 из 2 неудачна: нет кода домофона; далее 2026-09-06 08:00-11:00');

SELECT n.EventId,
       JSON_VALUE(m.substring_matches, '$[0].value') AS attempt,
       JSON_VALUE(m.substring_matches, '$[1].value') AS total,
       JSON_VALUE(m.substring_matches, '$[2].value') AS reason,
       TRY_CAST(JSON_VALUE(m.substring_matches, '$[3].value') AS date) AS next_date,
       JSON_VALUE(m.substring_matches, '$[4].value') AS window_from,
       JSON_VALUE(m.substring_matches, '$[5].value') AS window_to
FROM @notes AS n
OUTER APPLY REGEXP_MATCHES(n.Description, N'Попытка (\d+) из (\d+) неудачна: ([^;]+); далее (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})-(\d{2}:\d{2})') AS m
ORDER BY n.EventId;

-- 2. Лог сканера: разобранные и неразобранные строки
DECLARE @log nvarchar(400) = N'2026-09-02T04:10:11Z SCAN_IN FX0000000001 op=hub-42' + NCHAR(10) +
                             N'2026-09-02T04:10:15Z SCAN_OUT NP123456789RU op=hub-42' + NCHAR(10) +
                             N'строка с ошибкой';
SELECT l.ordinal AS line_no, l.value AS line,
       JSON_VALUE(m.substring_matches, '$[0].value') AS ts, JSON_VALUE(m.substring_matches, '$[1].value') AS op_code,
       JSON_VALUE(m.substring_matches, '$[2].value') AS tracking, JSON_VALUE(m.substring_matches, '$[3].value') AS operator,
       IIF(m.match_id IS NULL, 'unparsed', 'ok') AS parse_status
FROM REGEXP_SPLIT_TO_TABLE(@log, '\n') AS l
OUTER APPLY REGEXP_MATCHES(l.value, '^(\S+) (SCAN_IN|SCAN_OUT) (\S+) op=(\S+)$') AS m
ORDER BY l.ordinal;

-- 3. Список трек-номеров с разными разделителями → отправления; ненайденные отдельно
DECLARE @input nvarchar(1000) = N'fx 0000000001, NP123456789RU; cr-2026-000042' + NCHAR(10) + N'FX9999999999 ;; NP000000000XX';
SELECT p.ordinal, p.value AS raw_input, s.ShipmentId, s.TrackingNumber, IIF(s.ShipmentId IS NULL, 'not found', 'found') AS status
FROM REGEXP_SPLIT_TO_TABLE(@input, '\s*[,;\n]+\s*') AS p
LEFT JOIN ship.Shipment AS s ON s.TrackingNumberNormalized = ship.fn_NormalizeTrackingNumber(p.value)
WHERE p.value <> ''
ORDER BY p.ordinal;
GO

-- 4. STRING_SPLIT против REGEXP_SPLIT_TO_TABLE на простом разделителе (2 000 строк demo.Shipment × 5 элементов)
SET STATISTICS TIME ON;
SELECT COUNT(*) FROM demo.Shipment AS s CROSS APPLY STRING_SPLIT(CONCAT(s.TrackingNumber, ',', s.City, ',', s.Status, ',a,b'), ',', 1) AS x;
SELECT COUNT(*) FROM demo.Shipment AS s CROSS APPLY REGEXP_SPLIT_TO_TABLE(CONCAT(s.TrackingNumber, ',', s.City, ',', s.Status, ',a,b'), ',') AS x;
SET STATISTICS TIME OFF;
GO
