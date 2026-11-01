-- Pulse: генерация метрик за 3 дня с шагом 10 с (глава 15).
-- Ряды: 5 endpoint-ов × 2 хоста; счётчики http_requests_total и http_errors_total (монотонные, со сбросом раз в сутки),
-- датчик latency_ms. Инцидентные часы совпадают с generate_logs.sql (26, 14 и 3 часа назад).
INSERT INTO pulse.metrics (metric, labels, ts, value)
WITH
    3 * 86400 / 10 AS steps,
    ['/api/v1/orders', '/api/v1/users', '/checkout', '/pricing', '/home'] AS endpoints,
    ['api-1', 'api-2'] AS hosts,
    [toStartOfHour(now() - INTERVAL 26 HOUR), toStartOfHour(now() - INTERVAL 14 HOUR), toStartOfHour(now() - INTERVAL 3 HOUR)] AS incidents
SELECT
    metric,
    map('endpoint', endpoint, 'host', host) AS labels,
    ts,
    multiIf(
        metric = 'http_requests_total', toFloat64((step % 8640) * base_rate * 10),                     -- сброс раз в сутки
        metric = 'http_errors_total',   toFloat64((step % 8640) * base_rate * 10 * if(in_incident, 0.3, 0.01)),
                                         30 + base_rate * 4 + if(in_incident, 400, 0) + rand(4) % 20  -- latency_ms
    ) AS value
FROM (
    SELECT
        number,
        intDiv(number, 3) AS series_no,
        number % 3 AS metric_no,
        ['http_requests_total', 'http_errors_total', 'latency_ms'][metric_no + 1] AS metric,
        endpoints[(intDiv(series_no, 2) % 5) + 1] AS endpoint,
        hosts[(series_no % 2) + 1] AS host,
        intDiv(series_no, 10) AS step,
        toStartOfInterval(now() - INTERVAL 3 DAY, INTERVAL 10 SECOND) + toIntervalSecond(step * 10) AS ts,
        1 + (intDiv(series_no, 2) % 5) AS base_rate,
        arrayExists(h -> ts >= h AND ts < h + INTERVAL 1 HOUR, incidents) AS in_incident
    FROM numbers(3 * 86400 / 10 * 10 * 3)
);

SELECT metric, uniq(series_id) AS series, count() AS points, min(ts), max(ts) FROM pulse.metrics GROUP BY metric;
