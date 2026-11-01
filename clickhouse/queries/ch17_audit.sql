-- Pulse: аудиторские запросы (глава 17). Семь вопросов, на каждый — ответ за минуту.

-- 1. Кто входил и откуда; серии отказов входа (требует session_log в config/config.d/security.xml)
SELECT event_time, type, user, auth_type, client_address, client_name, failure_reason
FROM system.session_log WHERE event_date = today() AND type IN ('LoginFailure', 'LoginSuccess')
ORDER BY event_time DESC LIMIT 20;

SELECT user, client_address, count() AS failures, min(event_time) AS first, max(event_time) AS last
FROM system.session_log WHERE event_date = today() AND type = 'LoginFailure'
GROUP BY user, client_address HAVING failures >= 5 ORDER BY failures DESC;

-- 2. Кто читал чувствительные колонки за неделю
SELECT user, count() AS queries, min(event_time) AS first, max(event_time) AS last
FROM system.query_log
WHERE event_date >= today() - 7 AND type = 'QueryFinish'
  AND (has(columns, 'pulse.events.user_id') OR has(columns, 'pulse.events.session_id') OR has(columns, 'pulse.user_profiles.name'))
GROUP BY user ORDER BY queries DESC;

-- 3. Кто менял права и схему за месяц
SELECT event_time, user, query_kind, substring(query, 1, 120) AS q
FROM system.query_log
WHERE event_date >= today() - 30 AND type = 'QueryFinish'
  AND (query_kind IN ('Create', 'Drop', 'Alter', 'Rename', 'Grant', 'Revoke')
       OR query ILIKE 'CREATE USER%' OR query ILIKE 'CREATE ROLE%' OR query ILIKE 'CREATE ROW POLICY%' OR query ILIKE 'CREATE QUOTA%')
ORDER BY event_time DESC;

-- 4. Кто удалял данные (партиции, мутации)
SELECT event_time, event_type, table, partition_id, rows, query_id
FROM system.part_log
WHERE event_date >= today() - 7 AND event_type IN ('RemovePart', 'MutatePart') AND database = 'pulse'
ORDER BY event_time DESC LIMIT 20;

-- 5. Попытки доступа без прав
SELECT event_time, user, substring(query, 1, 100) AS q, exception_code
FROM system.query_log
WHERE event_date = today() AND type = 'ExceptionBeforeStart' AND exception_code = 497
ORDER BY event_time DESC LIMIT 20;

-- 6. Выгрузки наружу (в файл клиента или во внешние функции записи)
SELECT event_time, user, substring(query, 1, 120) AS q
FROM system.query_log
WHERE event_date >= today() - 7 AND type = 'QueryFinish'
  AND (query ILIKE '%INTO OUTFILE%' OR query ILIKE '%INSERT INTO FUNCTION s3%' OR query ILIKE '%INSERT INTO FUNCTION url%')
ORDER BY event_time DESC;

-- 7. Аудиторский след (база audit; только роль auditor и admin)
SELECT event_time, kind, user, client_address, substring(detail, 1, 80) AS detail
FROM audit.access_events WHERE event_time >= now() - INTERVAL 1 DAY ORDER BY event_time DESC LIMIT 50;

-- Выгрузка следа наружу (суточная; требует коллекцию minio_backups или аналог)
-- INSERT INTO FUNCTION s3(minio_backups, filename = 'audit/access_events-{_partition_id}.parquet', format = 'Parquet')
-- PARTITION BY toDate(event_time)
-- SELECT * FROM audit.access_events WHERE event_time >= today() - 1 AND event_time < today();
