-- Pulse: диагностика типовых аварий (глава 18). Порядок действий — docs/runbooks.md.

-- ===================== 1. TOO MANY PARTS =====================
-- Где: куски по партициям и средний размер (килобайты = мелкие вставки)
SELECT table, partition, count() AS parts, formatReadableSize(avg(bytes_on_disk)) AS avg_size, sum(rows) AS rows
FROM system.parts WHERE database = 'pulse' AND active
GROUP BY table, partition ORDER BY parts DESC LIMIT 5;

-- Кто: вставки за 30 минут по пользователю/клиенту
SELECT user, client_name, count() AS inserts, round(avg(written_rows)) AS avg_rows
FROM system.query_log
WHERE event_time >= now() - INTERVAL 30 MINUTE AND type = 'QueryFinish' AND query_kind = 'Insert' AND has(tables, 'pulse.events')
GROUP BY user, client_name ORDER BY inserts DESC;

-- Когда началось: темп создания кусков по часам
SELECT toStartOfHour(event_time) AS hour, count() AS new_parts, formatReadableSize(avg(size_in_bytes)) AS avg_size, uniq(query_id) AS inserts
FROM system.part_log
WHERE event_date >= today() - 1 AND database = 'pulse' AND table = 'events' AND event_type = 'NewPart'
GROUP BY hour ORDER BY hour;

-- Слияния идут? Предвестники?
SELECT database, table, elapsed, round(progress * 100) AS pct, num_parts FROM system.merges;
SELECT event, value FROM system.events WHERE event IN ('DelayedInserts', 'RejectedInserts');
SELECT table, countIf(active) AS active_parts, countIf(NOT active) AS inactive_parts FROM system.parts WHERE database = 'pulse' GROUP BY table;

-- Средний размер куска по таблицам (профилактика: килобайты — тревога)
SELECT table, count() AS parts, formatReadableSize(avg(bytes_on_disk)) AS avg_part FROM system.parts
WHERE database = 'pulse' AND active GROUP BY table ORDER BY avg(bytes_on_disk);

-- Действия (по руководству):
-- SYSTEM START MERGES pulse.events;
-- OPTIMIZE TABLE pulse.events PARTITION '202609';
-- ALTER TABLE pulse.events MODIFY SETTING parts_to_throw_insert = 6000, parts_to_delay_insert = 3000;  -- временно!
-- ALTER TABLE pulse.events MODIFY SETTING parts_to_throw_insert = 3000, parts_to_delay_insert = 1000;  -- вернуть
-- Воспроизведение на стенде: ALTER TABLE pulse.events MODIFY SETTING parts_to_throw_insert = 500, parts_to_delay_insert = 200;
--   python ingestion/app/emit_events.py --rate 200 --seconds 600 --max-rows 5 --max-seconds 0.05

-- ===================== 2. MEMORY LIMIT EXCEEDED =====================
-- Самые прожорливые за день (включая упавшие)
SELECT substring(query, 1, 80) AS q, user, formatReadableSize(memory_usage) AS peak, read_rows, result_rows, query_duration_ms, exception_code
FROM system.query_log WHERE event_date = today() AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
ORDER BY memory_usage DESC LIMIT 10;

-- Сейчас
SELECT query_id, user, elapsed, formatReadableSize(memory_usage) AS memory, substring(query, 1, 100) AS q
FROM system.processes ORDER BY memory_usage DESC LIMIT 5;
-- KILL QUERY WHERE query_id = '<query_id>';

-- Не запросы: словари, кэши, память сервера
SELECT name, formatReadableSize(bytes_allocated) AS memory FROM system.dictionaries ORDER BY bytes_allocated DESC;
SELECT metric, formatReadableSize(value) AS v FROM system.asynchronous_metrics
WHERE metric IN ('MemoryResident', 'OSMemoryTotal', 'OSMemoryAvailable', 'MarkCacheBytes', 'UncompressedCacheBytes');
SELECT formatReadableSize(value) AS tracked FROM system.metrics WHERE metric = 'MemoryTracking';
SELECT name, value FROM system.server_settings WHERE name IN ('max_server_memory_usage', 'max_server_memory_usage_to_ram_ratio');

-- Учебный отказ (практика 18.6): группировка с массивами при лимите 200 МБ
-- SELECT user_id, session_id, groupArray(event_type), groupArray(endpoint) FROM pulse.events
-- WHERE event_date >= today() - 30 GROUP BY user_id, session_id SETTINGS max_memory_usage = 200000000;
-- Лечение по ступеням: groupArray(20) и без endpoint → max_bytes_before_external_group_by = 100000000 → витрина сессий

-- ===================== 3. ЗАСТРЯВШАЯ МУТАЦИЯ =====================
SELECT table, mutation_id, parts_to_do, is_done, latest_fail_reason, dateDiff('minute', create_time, now()) AS running_min
FROM system.mutations WHERE database = 'pulse' AND NOT is_done;
-- KILL MUTATION WHERE database = 'pulse' AND table = 'events' AND NOT is_done;

-- ===================== 4. ОБЩИЙ СНИМОК (первые пять минут инцидента) =====================
SELECT query_id, user, elapsed, formatReadableSize(memory_usage) AS memory, substring(query, 1, 80) AS q FROM system.processes WHERE query NOT ILIKE '%system.processes%' ORDER BY elapsed DESC;
SELECT database, table, elapsed, num_parts FROM system.merges;
SELECT metric, value FROM system.asynchronous_metrics WHERE metric IN ('MaxPartCountForPartition', 'ReplicasMaxAbsoluteDelay', 'ReadonlyReplica');
SELECT name, code, value, last_error_time, substring(last_error_message, 1, 100) AS msg FROM system.errors WHERE value > 0 ORDER BY last_error_time DESC LIMIT 10;
SELECT name, formatReadableSize(free_space) AS free FROM system.disks;
