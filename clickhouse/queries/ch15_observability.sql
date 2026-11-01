-- Pulse: наблюдаемость (глава 15). Требует ddl/observability.sql и генераторы логов/метрик/спанов.

-- ===== 1. Расследование по идентификатору запроса: логи + спаны одного запроса =====
WITH (
    SELECT request_id FROM pulse.app_logs
    WHERE level = 'ERROR' AND hasToken(lower(message), 'timeout') AND ts >= now() - INTERVAL 1 DAY
    ORDER BY ts DESC LIMIT 1
) AS rid
SELECT 'log' AS kind, toString(ts) AS at, concat(service, ' ', level, ': ', message) AS detail
FROM pulse.app_logs WHERE request_id = rid AND ts >= now() - INTERVAL 1 DAY
UNION ALL
SELECT 'span', toString(start_ts), concat(service, ' ', operation, ' ', toString(duration_us / 1000), ' ms')
FROM pulse.spans WHERE request_id = rid AND start_ts >= now() - INTERVAL 1 DAY
ORDER BY at;

-- ===== 2. Форма инцидента в трёх видах телеметрии (пики должны совпасть по минутам) =====
SELECT minute, sum(lines) AS error_lines FROM pulse.logs_by_minute
WHERE level = 'ERROR' AND minute >= now() - INTERVAL 1 DAY GROUP BY minute ORDER BY error_lines DESC LIMIT 5;

SELECT toStartOfMinute(ts) AS minute, sum(deltaSumTimestamp(value, ts)) / 60 AS errors_per_sec
FROM pulse.metrics WHERE metric = 'http_errors_total' AND ts >= now() - INTERVAL 1 DAY
GROUP BY minute ORDER BY errors_per_sec DESC LIMIT 5;

SELECT toStartOfMinute(start_ts) AS minute, quantileTDigest(0.95)(duration_us) / 1000 AS p95_ms
FROM pulse.spans WHERE service = 'orders' AND start_ts >= now() - INTERVAL 1 DAY
GROUP BY minute ORDER BY p95_ms DESC LIMIT 5;

-- ===== 3. Логи: новые шаблоны сообщений за час =====
SELECT normalizeQuery(message) AS pattern, min(ts) AS first_seen, count() AS lines
FROM pulse.app_logs WHERE level = 'ERROR' AND ts >= now() - INTERVAL 1 DAY
GROUP BY pattern HAVING first_seen >= now() - INTERVAL 1 HOUR ORDER BY lines DESC;

-- ===== 4. Метрики: скорость запросов по endpoint-ам и перцентили из минутной витрины =====
SELECT toStartOfMinute(ts) AS minute, labels['endpoint'] AS endpoint, deltaSumTimestamp(value, ts) / 60 AS rps
FROM pulse.metrics WHERE metric = 'http_requests_total' AND ts >= now() - INTERVAL 1 HOUR
GROUP BY minute, endpoint ORDER BY minute, endpoint;

SELECT labels['endpoint'] AS endpoint, quantilesTDigestMerge(0.5, 0.95, 0.99)(quant) AS latency_p50_p95_p99
FROM pulse.metrics_1m WHERE metric = 'latency_ms' AND minute >= now() - INTERVAL 24 HOUR
GROUP BY endpoint ORDER BY endpoint;

-- Последнее значение датчика по хостам и молчащие источники
SELECT labels['host'] AS host, argMax(value, ts) AS latency_now, max(ts) AS as_of, now() - max(ts) AS silent_sec
FROM pulse.metrics WHERE metric = 'latency_ms' AND ts >= now() - INTERVAL 30 MINUTE GROUP BY host;

-- ===== 5. Здоровье сервера: показатели вне нормы (пусто на спокойном стенде) =====
SELECT metric, argMax(value, ts) AS current, max(ts) AS as_of
FROM pulse.ch_health WHERE ts >= now() - INTERVAL 5 MINUTE
GROUP BY metric
HAVING (metric = 'MaxPartCountForPartition' AND current > 300)
    OR (metric = 'ReadonlyReplica' AND current > 0)
    OR (metric = 'ReplicasMaxAbsoluteDelay' AND current > 60)
    OR (metric LIKE 'DiskAvailable_%' AND current < 5e9)
    OR (metric IN ('DelayedInserts', 'RejectedInserts') AND current > 0);

-- Доля отказов запросов за час (по приращениям счётчиков в истории здоровья)
SELECT round(100.0 * (maxIf(value, metric = 'FailedQuery') - minIf(value, metric = 'FailedQuery'))
                  / greatest(maxIf(value, metric = 'Query') - minIf(value, metric = 'Query'), 1), 2) AS failed_pct
FROM pulse.ch_health WHERE ts >= now() - INTERVAL 1 HOUR AND metric IN ('Query', 'FailedQuery');

-- ===== 6. Мониторинг запросов: показатели по панелям и длинные запросы сейчас =====
SELECT panel, sum(runs) AS runs, sum(failed) AS failed, round(max(p95_ms)) AS worst_p95_ms, sum(read_rows) AS read_rows
FROM pulse.query_health_1m WHERE minute >= now() - INTERVAL 1 HOUR GROUP BY panel ORDER BY runs DESC;

SELECT query_id, user, log_comment, elapsed, read_rows, formatReadableSize(memory_usage) AS memory, substring(query, 1, 100) AS q
FROM system.processes WHERE elapsed > 60 AND query NOT ILIKE '%system.processes%' ORDER BY elapsed DESC;

-- Спаны сервера (нужен SET opentelemetry_start_trace_probability = 1 или заголовок traceparent от клиента)
SELECT trace_id, operation_name, finish_time_us - start_time_us AS duration_us
FROM system.opentelemetry_span_log
WHERE start_time_us >= toUnixTimestamp64Micro(now64() - INTERVAL 10 MINUTE)
ORDER BY start_time_us DESC LIMIT 20;

-- ===== 7. Недельный обзор: растущие формы запросов =====
SELECT normalized_query_hash,
       sumIf(query_duration_ms, event_date >= today() - 7) AS this_week_ms,
       sumIf(query_duration_ms, event_date < today() - 7) AS prev_week_ms,
       round(this_week_ms / greatest(prev_week_ms, 1), 2) AS growth,
       any(substring(query, 1, 80)) AS sample
FROM system.query_log
WHERE event_date >= today() - 14 AND type = 'QueryFinish' AND query_kind = 'Select'
GROUP BY normalized_query_hash HAVING prev_week_ms > 1000 ORDER BY growth DESC LIMIT 10;

-- ===== 8. Сжатие таблиц телеметрии =====
SELECT table, sum(rows) AS rows, formatReadableSize(sum(data_compressed_bytes)) AS on_disk,
       round(sum(data_uncompressed_bytes) / greatest(sum(data_compressed_bytes), 1), 1) AS ratio
FROM system.parts WHERE database = 'pulse' AND table IN ('app_logs', 'app_logs_debug', 'metrics', 'metrics_1m', 'spans') AND active
GROUP BY table;
