-- Pulse: денормализация тарифа в события (глава 8).
-- ЗАВИСИМОСТЬ: словарь pulse.user_plan_current (ddl/dictionaries.sql) должен существовать —
-- иначе вставки в pulse.events начнут отказывать из-за DEFAULT-выражения.
-- DEFAULT, а не MATERIALIZED: источник может передать тариф явно, сервер подставляет только при отсутствии.

ALTER TABLE pulse.events
    ADD COLUMN IF NOT EXISTS plan LowCardinality(String)
    DEFAULT dictGetOrDefault('pulse.user_plan_current', 'plan', user_id, 'unknown');

-- Staging-таблица обязана повторять схему основной (иначе REPLACE PARTITION откажет)
ALTER TABLE pulse.events_staging
    ADD COLUMN IF NOT EXISTS plan LowCardinality(String)
    DEFAULT dictGetOrDefault('pulse.user_plan_current', 'plan', user_id, 'unknown');

-- Проверка совпадения схем: результат должен быть пустым
SELECT name, type FROM system.columns WHERE database = 'pulse' AND table = 'events'
EXCEPT
SELECT name, type FROM system.columns WHERE database = 'pulse' AND table = 'events_staging';

-- Заполнение истории семантикой «как было» (тариф на момент события) — по одному месяцу:
--   TRUNCATE TABLE pulse.events_staging;
--   INSERT INTO pulse.events_staging
--   SELECT * REPLACE (dictGet('pulse.user_plan_history_dict', 'plan', user_id, event_time) AS plan)
--   FROM pulse.events WHERE toYYYYMM(event_time) = 202609;
--   ALTER TABLE pulse.events REPLACE PARTITION '202609' FROM pulse.events_staging;
