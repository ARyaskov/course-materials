-- Pulse: набор диагностики (глава 12). Выполняется целиком за секунды; каждый блок — один вопрос.
-- Перед чтением свежих событий журнала: SYSTEM FLUSH LOGS;

-- ===================== СНИМОК ЗДОРОВЬЯ =====================

-- 1. Куски по партициям (норма: единицы-десятки активных кусков на партицию)
SELECT table, partition, count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS size, max(modification_time) AS last_modified
FROM system.parts WHERE database = 'pulse' AND active
GROUP BY table, partition ORDER BY parts DESC LIMIT 10;

-- 2. Слияния сейчас (норма: пусто или единицы с растущим progress)
SELECT database, table, elapsed, round(progress * 100) AS pct, formatReadableSize(total_size_bytes_compressed) AS size, num_parts
FROM system.merges;

-- 3. Незавершённые мутации (норма: пусто; latest_fail_reason должен быть пуст)
SELECT database, table, mutation_id, command, is_done, parts_to_do, latest_fail_reason
FROM system.mutations WHERE NOT is_done;

-- 4. Место: таблицы и диски
SELECT database, table, formatReadableSize(sum(bytes_on_disk)) AS size, sum(rows) AS rows
FROM system.parts WHERE active GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC LIMIT 10;
SELECT name, formatReadableSize(free_space) AS free, formatReadableSize(total_space) AS total FROM system.disks;

-- 5. Что выполняется сейчас
SELECT query_id, user, elapsed, read_rows, formatReadableSize(memory_usage) AS memory, substring(query, 1, 80) AS q
FROM system.processes WHERE query NOT ILIKE '%system.processes%' ORDER BY elapsed DESC;

-- 6. Ключевые метрики
SELECT metric, value FROM system.metrics
WHERE metric IN ('Query', 'Merge', 'PartMutation', 'MemoryTracking', 'TCPConnection', 'HTTPConnection');
SELECT metric, value FROM system.asynchronous_metrics
WHERE metric IN ('MaxPartCountForPartition', 'OSMemoryAvailable', 'DiskUsed_default');

-- 7. Ошибки сервера (по кодам, с момента старта)
SELECT name, code, value AS occurrences, last_error_time, substring(last_error_message, 1, 100) AS last_message
FROM system.errors WHERE value > 0 ORDER BY last_error_time DESC LIMIT 10;

-- 8. Словари, обновляемые представления, потребители Kafka
SELECT name, status, element_count, formatReadableSize(bytes_allocated) AS memory, last_exception
FROM system.dictionaries WHERE database = 'pulse';
SELECT view, status, last_success_time, next_refresh_time, exception FROM system.view_refreshes WHERE database = 'pulse';
SELECT table, num_messages_read, last_poll_time, num_commits, exceptions.text FROM system.kafka_consumers WHERE database = 'pulse';

-- 9. Настройки, отличающиеся от умолчаний
SELECT name, value FROM system.settings WHERE changed;

-- ===================== НАГРУЗКА ПО ЖУРНАЛУ =====================

-- 10. Самые дорогие формы запросов по сумме за 7 дней (кандидаты на витрины/проекции/индексы)
SELECT normalized_query_hash, count() AS runs, round(sum(query_duration_ms) / 1000) AS total_sec,
       round(avg(query_duration_ms)) AS avg_ms, formatReadableSize(max(memory_usage)) AS max_mem,
       sum(read_rows) AS rows_read, any(substring(query, 1, 100)) AS sample
FROM system.query_log
WHERE event_date >= today() - 7 AND type = 'QueryFinish' AND query_kind = 'Select' AND query NOT ILIKE '%system.%'
GROUP BY normalized_query_hash ORDER BY total_sec DESC LIMIT 10;

-- 11. Усиление чтения: прочитано / возвращено (фильтры вне ключа, отсутствующие витрины)
SELECT substring(query, 1, 100) AS q, read_rows, result_rows, round(read_rows / greatest(result_rows, 1)) AS amplification
FROM system.query_log
WHERE event_date = today() AND type = 'QueryFinish' AND query_kind = 'Select' AND read_rows > 1000000
ORDER BY amplification DESC LIMIT 10;

-- 12. Ошибки запросов по кодам за сегодня
SELECT exception_code, count() AS errors, any(substring(exception, 1, 120)) AS sample_message, any(user) AS sample_user
FROM system.query_log
WHERE event_date = today() AND type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')
GROUP BY exception_code ORDER BY errors DESC;

-- 13. Запросы по меткам (SETTINGS log_comment = 'dashboard:activity')
SELECT log_comment, count() AS runs, round(avg(query_duration_ms)) AS avg_ms, sum(read_rows) AS rows_read
FROM system.query_log
WHERE event_date = today() AND type = 'QueryFinish' AND log_comment != ''
GROUP BY log_comment ORDER BY runs DESC;

-- ===================== РАЗБОР ОДНОГО ЗАПРОСА =====================

-- 14. Счётчики профилирования последних запросов к событиям
SELECT substring(query, 1, 60) AS q, ProfileEvents['SelectedParts'] AS parts, ProfileEvents['SelectedMarks'] AS marks,
       formatReadableSize(ProfileEvents['ReadCompressedBytes']) AS read_compressed,
       round(ProfileEvents['OSCPUVirtualTimeMicroseconds'] / 1000) AS cpu_ms, query_duration_ms, projections
FROM system.query_log
WHERE event_date = today() AND type = 'QueryFinish' AND query ILIKE '%FROM pulse.events%'
ORDER BY event_time DESC LIMIT 5;

-- 15. Где именно время: процессоры конвейера (нужен SET log_processors_profiles = 1; подставьте query_id)
SELECT name, round(sum(elapsed_us) / 1000) AS elapsed_ms, sum(input_rows) AS rows_in, count() AS instances
FROM system.processors_profile_log
WHERE event_date = today() AND query_id = '<query_id>'
GROUP BY name ORDER BY elapsed_ms DESC LIMIT 8;

-- 16. Попадания в кэши (результатов, условий) по счётчикам
SELECT substring(query, 1, 60) AS q, read_rows, formatReadableSize(read_bytes) AS read,
       mapFilter((k, v) -> k ILIKE '%QueryCache%' OR k ILIKE '%ConditionCache%', ProfileEvents) AS cache_events
FROM system.query_log
WHERE event_date = today() AND type = 'QueryFinish' AND query ILIKE '%FROM pulse.events%'
ORDER BY event_time DESC LIMIT 5;

-- ===================== ТИПОВЫЕ СЛУЧАИ ИЗ ПРАКТИКИ 12.6 =====================

-- Случай 1: фильтр вне ключа + широкая колонка -> читать из витрины с подходящим ключом
EXPLAIN indexes = 1
SELECT event_time, endpoint, attributes['message'] FROM pulse.events
WHERE event_date >= today() - 7 AND status >= 500 ORDER BY event_time DESC LIMIT 50;
SELECT event_time, endpoint, attributes['message'] AS message FROM pulse.events_errors
WHERE event_time >= now() - INTERVAL 7 DAY ORDER BY event_time DESC LIMIT 50;

-- Случай 2: память на группировке -> ограничить состояния / внешняя агрегация / витрина
SELECT user_id, toStartOfHour(event_time) AS hour, uniq(session_id) AS sessions
FROM pulse.events WHERE event_date >= today() - 30
GROUP BY user_id, hour
SETTINGS max_memory_usage = 500000000, max_bytes_before_external_group_by = 200000000;

-- Случай 3: соединение не той стороной -> схлопнутый справочник справа или денормализованная колонка
EXPLAIN
SELECT p.plan, count() FROM pulse.user_profiles AS p JOIN pulse.events AS e ON e.user_id = p.user_id
WHERE e.event_date >= today() - 30 GROUP BY p.plan;
SELECT plan, count() FROM pulse.events WHERE event_date >= today() - 30 GROUP BY plan;
