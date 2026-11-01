-- Pulse: производные колонки, вычисляемые при вставке (глава 7).
-- Нормализованный endpoint: /api/v1/orders/48213 -> /api/v1/orders/{id}
ALTER TABLE pulse.events
    ADD COLUMN IF NOT EXISTS endpoint_group LowCardinality(String)
    MATERIALIZED replaceRegexpAll(endpoint, '/\\d+', '/{id}');

-- Заполнить для уже существующих кусков (иначе вычислится при слиянии)
ALTER TABLE pulse.events MATERIALIZE COLUMN endpoint_group;

-- Staging-таблица должна повторять схему основной (иначе REPLACE PARTITION откажет)
ALTER TABLE pulse.events_staging
    ADD COLUMN IF NOT EXISTS endpoint_group LowCardinality(String)
    MATERIALIZED replaceRegexpAll(endpoint, '/\\d+', '/{id}');

-- Проверка
SELECT endpoint_group, count() AS hits
FROM pulse.events
GROUP BY endpoint_group
ORDER BY hits DESC;
