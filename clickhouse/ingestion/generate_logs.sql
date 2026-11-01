-- Pulse: генерация 2 млн строк логов за последние 3 дня (глава 9).
-- Пять сервисов, уровни с перекосом в INFO, ~5 строк на request_id,
-- слово "timeout" — около 1 % строк, сосредоточенных в трёх «инцидентных» часах.
-- rand(N) с разными аргументами — чтобы одинаковые вызовы rand() не были склеены как общее подвыражение.

INSERT INTO pulse.app_logs (ts, service, level, request_id, user_id, endpoint, message, labels)
SELECT
    toDateTime64(base_ts, 3) + toIntervalMillisecond(rand(1) % 1000)               AS ts,
    ['orders', 'billing', 'auth', 'catalog', 'gateway'][(rand(2) % 5) + 1]         AS service,
    multiIf(in_incident AND dice < 40, 'ERROR', dice < 3, 'ERROR', dice < 10, 'WARN', 'INFO') AS level,
    -- пять строк подряд получают один request_id; UUID собирается из 32 hex-символов двух хешей
    toUUID(concat(substring(h, 1, 8), '-', substring(h, 9, 4), '-', substring(h, 13, 4), '-',
                  substring(h, 17, 4), '-', substring(h, 21, 12)))                  AS request_id,
    (req % 1000) + 1                                                                AS user_id,
    ['/api/v1/orders', '/api/v1/users', '/checkout', '/pricing', '/home'][(req % 5) + 1] AS endpoint,
    multiIf(
        level = 'ERROR' AND in_incident, concat('upstream timeout after ', toString(1000 + rand(3) % 4000), 'ms calling ', endpoint),
        level = 'ERROR',                 ['connection refused by database', 'invalid token signature', 'order not found', 'payment provider unavailable'][(rand(4) % 4) + 1],
        level = 'WARN',                  ['retrying request', 'slow query detected', 'cache miss ratio high'][(rand(5) % 3) + 1],
                                         concat('handled ', endpoint, ' in ', toString(rand(6) % 300), 'ms')
    )                                                                               AS message,
    mapFilter((k, v) -> v != '',
        map('pod',     concat(service, '-', toString(rand(7) % 4)),
            'version', if(base_ts >= now() - INTERVAL 1 DAY, '2.4.1', '2.4.0'),
            'canary',  if(rand(8) % 50 = 0, 'true', '')))                          AS labels
FROM (
    SELECT number,
           intDiv(number, 5)                                              AS req,
           lower(concat(hex(cityHash64(req)), hex(sipHash64(req))))       AS h,
           now() - toIntervalSecond(rand(9) % (3 * 86400))                AS base_ts,
           rand(10) % 100                                                 AS dice,
           arrayExists(x -> base_ts >= x AND base_ts < x + INTERVAL 1 HOUR,
                       [toStartOfHour(now() - INTERVAL 26 HOUR),
                        toStartOfHour(now() - INTERVAL 14 HOUR),
                        toStartOfHour(now() - INTERVAL 3 HOUR)])          AS in_incident
    FROM numbers(2000000)
);

-- Проверка
SELECT service, level, count() AS lines FROM pulse.app_logs GROUP BY service, level ORDER BY service, level;
SELECT countIf(hasToken(lower(message), 'timeout')) AS timeout_lines, count() AS total FROM pulse.app_logs;
