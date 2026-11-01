-- Pulse: backfill инкрементальных витрин за месяц заменой партиций (глава 10).
-- Шаблон: замените 202609 на нужный месяц (YYYYMM) во всех местах.
-- Запросы обязаны совпадать с запросами представлений в ddl/materialized_views.sql.
-- Для текущего месяца граница двойного учёта проходит по received_at (момент создания представления),
-- для прошлых месяцев замена партиции делает backfill идемпотентным без дополнительных условий.

-- ---------- events_hourly ----------
TRUNCATE TABLE pulse.events_hourly_staging;
INSERT INTO pulse.events_hourly_staging
SELECT toStartOfHour(event_time) AS hour, event_type,
       count() AS events, countIf(status >= 500) AS errors, sum(ifNull(amount, 0)) AS revenue
FROM pulse.events
WHERE toYYYYMM(event_time) = 202609
GROUP BY hour, event_type;
ALTER TABLE pulse.events_hourly REPLACE PARTITION '202609' FROM pulse.events_hourly_staging;

-- ---------- endpoint_hourly ----------
TRUNCATE TABLE pulse.endpoint_hourly_staging;
INSERT INTO pulse.endpoint_hourly_staging
SELECT toStartOfHour(event_time) AS hour, endpoint_group,
       count() AS requests, countIf(status >= 500) AS failures,
       sum(toUInt32OrZero(attributes['latency_ms'])) AS latency_sum,
       countIf(mapContains(attributes, 'latency_ms')) AS latency_count
FROM pulse.events
WHERE toYYYYMM(event_time) = 202609 AND endpoint_group LIKE '/api/%'
GROUP BY hour, endpoint_group;
ALTER TABLE pulse.endpoint_hourly REPLACE PARTITION '202609' FROM pulse.endpoint_hourly_staging;

-- ---------- events_hourly_users ----------
TRUNCATE TABLE pulse.events_hourly_users_staging;
INSERT INTO pulse.events_hourly_users_staging
SELECT toStartOfHour(event_time) AS hour, country,
       uniqCombinedState(user_id) AS users,
       uniqCombinedIfState(user_id, event_type = 'purchase') AS buyers,
       quantilesTDigestState(0.5, 0.95, 0.99)(toUInt32OrZero(attributes['latency_ms'])) AS latency,
       count() AS events,
       sum(ifNull(amount, 0)) AS revenue
FROM pulse.events
WHERE toYYYYMM(event_time) = 202609
GROUP BY hour, country;
ALTER TABLE pulse.events_hourly_users REPLACE PARTITION '202609' FROM pulse.events_hourly_users_staging;

-- ---------- Сверка: часы, где витрина расходится с событиями (ожидается пустой результат) ----------
SELECT h.hour, h.events_view, e.events_direct, h.users_view, e.users_direct
FROM (
    SELECT hour, sum(events) AS events_view, uniqCombinedMerge(users) AS users_view
    FROM pulse.events_hourly_users WHERE toYYYYMM(hour) = 202609 GROUP BY hour
) AS h
JOIN (
    SELECT toStartOfHour(event_time) AS hour, count() AS events_direct, uniqCombined(user_id) AS users_direct
    FROM pulse.events WHERE toYYYYMM(event_time) = 202609 GROUP BY hour
) AS e USING (hour)
WHERE h.events_view != e.events_direct OR h.users_view != e.users_direct
ORDER BY hour;
