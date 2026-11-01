-- Pulse: проверка проекций (глава 11). Требует: ddl/projections.sql (проекции материализованы).

-- ===== 1. Базовая линия: те же запросы без проекций =====
SELECT event_time, event_type, endpoint, status
FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90
ORDER BY event_time
SETTINGS optimize_use_projections = 0;

SELECT event_time, user_id, event_type, status
FROM pulse.events
WHERE endpoint_group = '/api/v1/orders/{id}' AND event_date >= today() - 90
ORDER BY event_time DESC LIMIT 100
SETTINGS optimize_use_projections = 0;

-- ===== 2. С проекциями =====
SELECT event_time, event_type, endpoint, status
FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90
ORDER BY event_time;

SELECT event_time, user_id, event_type, status
FROM pulse.events
WHERE endpoint_group = '/api/v1/orders/{id}' AND event_date >= today() - 90
ORDER BY event_time DESC LIMIT 100;

-- Сравнение по журналу: read_rows и projections
SELECT substring(query, 1, 70) AS q, read_rows, query_duration_ms, projections
FROM system.query_log
WHERE type = 'QueryFinish' AND event_time >= now() - INTERVAL 10 MINUTE
  AND (query ILIKE '%user_id = 42%' OR query ILIKE '%orders/{id}%')
ORDER BY event_time DESC LIMIT 4;

-- ===== 3. План =====
EXPLAIN indexes = 1
SELECT event_time, event_type, endpoint, status
FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90
ORDER BY event_time;

-- Узкий период: планировщик вправе оставить основной порядок — это норма
EXPLAIN indexes = 1
SELECT event_time, event_type FROM pulse.events
WHERE user_id = 42 AND event_time >= now() - INTERVAL 1 HOUR;

-- Лишняя колонка (attributes нет в p_by_user): чтение уходит на основной порядок без ошибки
EXPLAIN indexes = 1
SELECT event_time, event_type, attributes FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90;

-- ===== 4. Покрытие кусков и объём =====
SELECT count() AS parts,
       countIf(has(projections, 'p_by_user')) AS with_by_user,
       countIf(has(projections, 'p_by_endpoint')) AS with_by_endpoint
FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active;

SELECT name, formatReadableSize(sum(bytes_on_disk)) AS size, sum(rows) AS rows
FROM system.projection_parts
WHERE database = 'pulse' AND table = 'events' AND active
GROUP BY name;

-- Оценка до создания (для сравнения): сжатый размер колонок проекции
SELECT formatReadableSize(sum(data_compressed_bytes)) AS p_by_user_estimate
FROM system.columns
WHERE database = 'pulse' AND table = 'events'
  AND name IN ('user_id', 'event_time', 'event_type', 'endpoint', 'status', 'amount');

-- ===== 5. Совместимость staging =====
SELECT table, name FROM system.projections
WHERE database = 'pulse' AND table IN ('events', 'events_staging')
ORDER BY table, name;

-- ===== 6. Проверки на регрессии: запрос упадёт, если проекция не используется =====
SELECT count() FROM pulse.events
WHERE user_id = 42 AND event_date >= today() - 90
SETTINGS force_optimize_projection_name = 'p_by_user';

SELECT count() FROM pulse.events
WHERE endpoint_group = '/api/v1/orders/{id}' AND event_date >= today() - 90
SETTINGS force_optimize_projection_name = 'p_by_endpoint';

-- ===== 7. Цена на вставке: средняя длительность вставок загрузчика за последние 5 минут =====
SELECT count() AS inserts, round(avg(query_duration_ms), 1) AS avg_ms, sum(written_rows) AS rows
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Insert' AND event_time >= now() - INTERVAL 5 MINUTE
  AND has(tables, 'pulse.events_in');
