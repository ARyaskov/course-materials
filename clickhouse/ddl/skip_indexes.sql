-- Pulse: индексы пропуска данных для pulse.events (глава 9).
-- Каждый индекс существует ради конкретного запроса (см. queries/ch9_search.sql):
--   idx_session   — разбор одной сессии:      WHERE event_date = D AND session_id = X
--   idx_received  — свежие поступления/лаг:   WHERE event_date = D AND received_at >= now() - INTERVAL 10 MINUTE
--   idx_attr_keys — редкие атрибуты:          WHERE mapContains(attributes, 'coupon')
--   idx_status    — учебный: на равномерных данных не работает, удаляется в конце практики.

ALTER TABLE pulse.events
    ADD COLUMN IF NOT EXISTS received_at DateTime DEFAULT now(),
    ADD INDEX IF NOT EXISTS idx_session   session_id          TYPE bloom_filter(0.01) GRANULARITY 2,
    ADD INDEX IF NOT EXISTS idx_received  received_at         TYPE minmax             GRANULARITY 4,
    ADD INDEX IF NOT EXISTS idx_attr_keys mapKeys(attributes) TYPE bloom_filter(0.01) GRANULARITY 4,
    ADD INDEX IF NOT EXISTS idx_status    status              TYPE set(8)             GRANULARITY 4;

-- Staging-таблица повторяет схему основной (индексы для REPLACE PARTITION не обязательны, колонки — да)
ALTER TABLE pulse.events_staging
    ADD COLUMN IF NOT EXISTS received_at DateTime DEFAULT now();

-- Сводки для уже существующих кусков (мутации; дождаться is_done = 1 в system.mutations)
ALTER TABLE pulse.events MATERIALIZE INDEX idx_session;
ALTER TABLE pulse.events MATERIALIZE INDEX idx_received;
ALTER TABLE pulse.events MATERIALIZE INDEX idx_attr_keys;
ALTER TABLE pulse.events MATERIALIZE INDEX idx_status;

SELECT name, type, expr, granularity, formatReadableSize(data_compressed_bytes) AS size
FROM system.data_skipping_indices
WHERE database = 'pulse' AND table = 'events';

-- После измерений (практика 9.6): учебный индекс удаляется
-- ALTER TABLE pulse.events DROP INDEX idx_status;
