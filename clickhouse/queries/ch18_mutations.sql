-- Pulse: мутации и долгие операции (глава 18).

-- ===== Наблюдение =====
SELECT table, mutation_id, command, create_time, is_done, parts_to_do, latest_failed_part, latest_fail_reason,
       dateDiff('minute', create_time, now()) AS running_min
FROM system.mutations WHERE database = 'pulse' ORDER BY create_time DESC LIMIT 10;

SELECT table, count() AS mutated_parts, round(avg(duration_ms) / 1000) AS avg_sec, formatReadableSize(sum(size_in_bytes)) AS rewritten
FROM system.part_log WHERE event_date = today() AND event_type = 'MutatePart' AND database = 'pulse' GROUP BY table;

-- ===== Оценка объёма до мутации: сколько кусков/байт затронет условие по периоду =====
SELECT count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS to_rewrite
FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active AND max_time >= now() - INTERVAL 7 DAY;

-- ===== Снятие застрявшей мутации =====
-- KILL MUTATION WHERE database = 'pulse' AND table = 'events' AND mutation_id = '<id>';

-- ===== Процедура: удаление данных пользователя по требованию (все места, где данные живут) =====
-- 1. События и логи — облегчённое удаление (физически — при слиянии)
-- DELETE FROM pulse.events   WHERE user_id = 424242;
-- DELETE FROM pulse.app_logs WHERE user_id = 424242;
-- DELETE FROM pulse.user_profiles WHERE user_id = 424242;
-- 2. Витрины с состояниями по пользователю не существуют (агрегаты по странам/часам не содержат идентификатора);
--    векторы поведения: DELETE FROM pulse.user_behavior_vectors WHERE user_id = 424242;
-- 3. Озеро: перезапись затронутых месяцев (чтение с фильтром, запись в новый префикс, удаление старого) — ingestion/export_lake.sql
-- 4. Копии: удаление истекает по ротации копий (срок записать в ответе на запрос)
-- Проверка: SELECT count() FROM pulse.events WHERE user_id = 424242;  -- 0

-- ===== Процедура: исправление периода через staging + REPLACE PARTITION (вместо ALTER UPDATE) =====
-- TRUNCATE TABLE pulse.events_staging;
-- INSERT INTO pulse.events_staging SELECT * REPLACE (toUInt16OrZero(attributes['latency_ms']) AS status) FROM pulse.events WHERE toYYYYMM(event_time) = 202609;
-- SELECT count() FROM pulse.events_staging;
-- ALTER TABLE pulse.events REPLACE PARTITION '202609' FROM pulse.events_staging;

-- ===== Учебная застрявшая мутация (практика 18.6): приведение падает на части строк =====
-- ALTER TABLE pulse.events UPDATE status = toUInt16(attributes['latency_ms']) WHERE event_date >= today() - 7;
-- Безопасный вариант после снятия: toUInt16OrZero(...) SETTINGS mutations_sync = 1

-- ===== Дешёвые изменения схемы (метаданные) для сравнения =====
-- ALTER TABLE pulse.events ADD COLUMN IF NOT EXISTS note String DEFAULT '';   -- мгновенно
-- ALTER TABLE pulse.events DROP COLUMN note;                                  -- мутация, удаляет файлы, не переписывает остальное
