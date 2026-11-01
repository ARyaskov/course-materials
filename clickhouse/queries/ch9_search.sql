-- Pulse: индексы пропуска и поиск (глава 9).
-- Требует: ddl/skip_indexes.sql, ddl/logs.sql, ingestion/generate_logs.sql.

-- ===== 1. Оценка локальности ДО индекса: доля блоков (32768 строк), содержащих значение =====
WITH 8192 * 4 AS block_rows
SELECT
    round(100 * countIf(has_status_500) / count(), 1)  AS pct_blocks_status_500,
    round(100 * countIf(has_coupon) / count(), 1)      AS pct_blocks_coupon,
    round(100 * countIf(has_latency) / count(), 1)     AS pct_blocks_latency,
    round(100 * countIf(has_session) / count(), 1)     AS pct_blocks_one_session
FROM (
    SELECT _part, intDiv(_part_offset, block_rows) AS block,
           max(status = 500)                          AS has_status_500,
           max(mapContains(attributes, 'coupon'))     AS has_coupon,
           max(mapContains(attributes, 'latency_ms')) AS has_latency,
           max(session_id = (SELECT any(session_id) FROM pulse.events WHERE event_date = today())) AS has_session
    FROM pulse.events
    GROUP BY _part, block
);

-- Различных значений в блоке (для set/bloom_filter)
WITH 8192 * 4 AS block_rows
SELECT quantiles(0.5, 0.95)(distinct_sessions) AS sessions_per_block_p50_p95
FROM (SELECT _part, intDiv(_part_offset, block_rows) AS block, uniqExact(session_id) AS distinct_sessions
      FROM pulse.events GROUP BY _part, block);

-- ===== 2. План: сколько гранул отсеял каждый индекс =====
EXPLAIN indexes = 1
SELECT count() FROM pulse.events
WHERE event_date = today() AND session_id = (SELECT any(session_id) FROM pulse.events WHERE event_date = today());

EXPLAIN indexes = 1
SELECT count() FROM pulse.events WHERE event_date = today() AND status = 500;

-- ===== 3. Факт: read_rows с индексами и без =====
WITH (SELECT any(session_id) FROM pulse.events WHERE event_date = today()) AS sid
SELECT count() FROM pulse.events WHERE event_date = today() AND session_id = sid SETTINGS use_skip_indexes = 0;
WITH (SELECT any(session_id) FROM pulse.events WHERE event_date = today()) AS sid
SELECT count() FROM pulse.events WHERE event_date = today() AND session_id = sid SETTINGS use_skip_indexes = 1;

SELECT substring(query, 1, 70) AS q, query_duration_ms, read_rows
FROM system.query_log
WHERE type = 'QueryFinish' AND query ILIKE '%session_id = sid%' AND event_time >= now() - INTERVAL 5 MINUTE
ORDER BY event_time DESC LIMIT 2;

-- ===== 4. Поиск по логам =====
-- по ключу (service, level, ts): узкий диапазон, чтение в порядке ключа
SELECT ts, request_id, message FROM pulse.app_logs
WHERE service = 'orders' AND level = 'ERROR' AND ts >= now() - INTERVAL 6 HOUR
ORDER BY ts DESC LIMIT 100;

-- по идентификатору запроса (bloom_filter) — всегда с условием по времени
WITH (SELECT any(request_id) FROM pulse.app_logs WHERE ts >= now() - INTERVAL 1 HOUR) AS rid
SELECT ts, service, level, message FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND request_id = rid ORDER BY ts;

-- по слову (текстовый индекс на lower(message))
SELECT service, count() AS lines, min(ts) AS first_seen, max(ts) AS last_seen
FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND hasToken(lower(message), 'timeout')
GROUP BY service ORDER BY lines DESC;

-- токен + регулярное выражение: индекс сужает, regex уточняет
SELECT ts, message FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY
  AND hasToken(lower(message), 'timeout') AND match(message, 'timeout after (\\d{4,}) ?ms')
ORDER BY ts DESC LIMIT 50;

-- LIKE (без индекса) против hasToken (с индексом): сравнить read_rows/read_bytes в query_log
SELECT count() FROM pulse.app_logs WHERE ts >= now() - INTERVAL 1 DAY AND message LIKE '%timeout%';
SELECT count() FROM pulse.app_logs WHERE ts >= now() - INTERVAL 1 DAY AND hasToken(lower(message), 'timeout');

-- редкая метка через индекс по ключам Map
SELECT count() FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND mapContains(labels, 'canary') AND labels['canary'] = 'true';

-- ===== 5. Проверки на регрессии: запрос упадёт, если индекс не применяется =====
SELECT count() FROM pulse.events
WHERE event_date = today() AND session_id = toUUID('00000000-0000-0000-0000-000000000000')
SETTINGS force_data_skipping_indices = 'idx_session';

SELECT count() FROM pulse.events
WHERE event_date = today() AND mapContains(attributes, 'coupon')
SETTINGS force_data_skipping_indices = 'idx_attr_keys';

SELECT count() FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND request_id = toUUID('00000000-0000-0000-0000-000000000000')
SETTINGS force_data_skipping_indices = 'idx_request';

SELECT count() FROM pulse.app_logs
WHERE ts >= now() - INTERVAL 1 DAY AND hasToken(lower(message), 'timeout')
SETTINGS force_data_skipping_indices = 'idx_message';

-- ===== 6. Размер индексов =====
SELECT table, name, type, formatReadableSize(data_compressed_bytes) AS size
FROM system.data_skipping_indices
WHERE database = 'pulse' ORDER BY table, name;
