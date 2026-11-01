-- Pulse: слой витрин (глава 10). Файл идемпотентен: таблицы — IF NOT EXISTS, представления — CREATE OR REPLACE.
-- Требует: ddl/retention.sql, ddl/derived_columns.sql (endpoint_group), ddl/user_profiles.sql (для снимков тарифов).
-- В сборках без CREATE OR REPLACE для материализованных представлений используйте
-- CREATE MATERIALIZED VIEW IF NOT EXISTS ... / ALTER TABLE <mv> MODIFY QUERY ...

-- ===================== Инкрементальные витрины (триггеры на вставку в events) =====================

-- 1. События, ошибки, выручка по часам и типам (SummingMergeTree: суммы складываются при слиянии)
CREATE TABLE IF NOT EXISTS pulse.events_hourly
(
    hour       DateTime,
    event_type LowCardinality(String),
    events     UInt64,
    errors     UInt64,
    revenue    Decimal(18, 2)
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, event_type);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_events_hourly TO pulse.events_hourly AS
SELECT toStartOfHour(event_time) AS hour,
       event_type,
       count()                    AS events,
       countIf(status >= 500)     AS errors,
       sum(ifNull(amount, 0))     AS revenue
FROM pulse.events
GROUP BY hour, event_type;

-- 2. Ошибки: та же структура, другой ключ — под запрос «ошибки endpoint-а за период»
CREATE TABLE IF NOT EXISTS pulse.events_errors AS pulse.events
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (endpoint_group, event_time)
TTL event_time + INTERVAL 30 DAY;

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_events_errors TO pulse.events_errors AS
SELECT * FROM pulse.events WHERE status >= 500;

-- 3. Запросы API по часам и группам endpoint-ов; среднее НЕ хранится — сумма и число
CREATE TABLE IF NOT EXISTS pulse.endpoint_hourly
(
    hour           DateTime,
    endpoint_group LowCardinality(String),
    requests       UInt64,
    failures       UInt64,
    latency_sum    UInt64,
    latency_count  UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, endpoint_group);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_endpoint_hourly TO pulse.endpoint_hourly AS
SELECT toStartOfHour(event_time)                          AS hour,
       endpoint_group,
       count()                                            AS requests,
       countIf(status >= 500)                             AS failures,
       sum(toUInt32OrZero(attributes['latency_ms']))      AS latency_sum,
       countIf(mapContains(attributes, 'latency_ms'))     AS latency_count
FROM pulse.events
WHERE endpoint_group LIKE '/api/%'
GROUP BY hour, endpoint_group;

-- 4. Состояния: уникальные пользователи, покупатели, квантили задержек по часам и странам
CREATE TABLE IF NOT EXISTS pulse.events_hourly_users
(
    hour     DateTime,
    country  LowCardinality(String),
    users    AggregateFunction(uniqCombined, UInt64),
    buyers   AggregateFunction(uniqCombined, UInt64),
    latency  AggregateFunction(quantilesTDigest(0.5, 0.95, 0.99), UInt32),
    events   SimpleAggregateFunction(sum, UInt64),
    revenue  SimpleAggregateFunction(sum, Decimal(18, 2))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, country);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_events_hourly_users TO pulse.events_hourly_users AS
SELECT toStartOfHour(event_time)                                                       AS hour,
       country,
       uniqCombinedState(user_id)                                                      AS users,
       uniqCombinedIfState(user_id, event_type = 'purchase')                           AS buyers,
       quantilesTDigestState(0.5, 0.95, 0.99)(toUInt32OrZero(attributes['latency_ms'])) AS latency,
       count()                                                                         AS events,
       sum(ifNull(amount, 0))                                                          AS revenue
FROM pulse.events
GROUP BY hour, country;

-- Staging-таблицы витрин для backfill заменой партиций (ingestion/backfill_views.sql)
CREATE TABLE IF NOT EXISTS pulse.events_hourly_staging       AS pulse.events_hourly;
CREATE TABLE IF NOT EXISTS pulse.endpoint_hourly_staging     AS pulse.endpoint_hourly;
CREATE TABLE IF NOT EXISTS pulse.events_hourly_users_staging AS pulse.events_hourly_users;

-- Обычное представление для инструментов: прячет комбинаторы Merge
CREATE OR REPLACE VIEW pulse.v_hourly_activity AS
SELECT hour, country,
       uniqCombinedMerge(users)  AS users,
       uniqCombinedMerge(buyers) AS buyers,
       sum(events)               AS events,
       sum(revenue)              AS revenue
FROM pulse.events_hourly_users
GROUP BY hour, country;

-- ===================== Обновляемые витрины (по расписанию) =====================

-- 5. Удержание по недельным когортам за 90 дней (пересчёт целиком раз в час)
CREATE TABLE IF NOT EXISTS pulse.retention_weekly
(
    cohort       Date,
    week_no      UInt16,
    users        UInt64,
    retained_pct Float32
)
ENGINE = MergeTree
ORDER BY (cohort, week_no);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_retention_weekly
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
TO pulse.retention_weekly AS
SELECT cohort, week_no, uniq(user_id) AS users,
       round(100.0 * users / max(users) OVER (PARTITION BY cohort), 1) AS retained_pct
FROM (
    SELECT user_id, toMonday(min(event_date)) AS cohort, groupUniqArray(toMonday(event_date)) AS weeks
    FROM pulse.events
    WHERE event_date >= today() - 90
    GROUP BY user_id
)
ARRAY JOIN weeks AS week
WHERE week >= cohort
GROUP BY cohort, dateDiff('week', cohort, week) AS week_no;

-- 6. Сводка удержания по возрасту когорты — ждёт завершения обновления удержания
CREATE TABLE IF NOT EXISTS pulse.retention_summary
(
    week_no          UInt16,
    avg_retained_pct Float32,
    cohorts          UInt64
)
ENGINE = MergeTree
ORDER BY week_no;

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_retention_summary
REFRESH EVERY 1 HOUR DEPENDS ON pulse.mv_retention_weekly
TO pulse.retention_summary AS
SELECT week_no, round(avg(retained_pct), 1) AS avg_retained_pct, count() AS cohorts
FROM pulse.retention_weekly
WHERE cohort >= today() - 90
GROUP BY week_no;

-- 7. Ежедневный снимок распределения по тарифам (APPEND: история состояния, которого нет в событиях)
CREATE TABLE IF NOT EXISTS pulse.plan_snapshot_daily
(
    snapshot_date Date,
    plan          LowCardinality(String),
    users         UInt64
)
ENGINE = MergeTree
ORDER BY (snapshot_date, plan);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_plan_snapshot_daily
REFRESH EVERY 1 DAY OFFSET 1 HOUR
APPEND TO pulse.plan_snapshot_daily AS
SELECT today() AS snapshot_date, plan, count() AS users
FROM (SELECT user_id, argMax(plan, updated_at) AS plan FROM pulse.user_profiles GROUP BY user_id)
GROUP BY plan;

-- 8. Топ-10 endpoint-ов за вчера — поверх инкрементальной витрины, а не событий
CREATE TABLE IF NOT EXISTS pulse.top_endpoints_daily
(
    day            Date,
    endpoint_group LowCardinality(String),
    requests       UInt64
)
ENGINE = MergeTree
ORDER BY (day, requests);

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_top_endpoints_daily
REFRESH EVERY 1 DAY OFFSET 2 HOUR
TO pulse.top_endpoints_daily AS
SELECT toDate(hour) AS day, endpoint_group, sum(requests) AS requests
FROM pulse.endpoint_hourly
WHERE hour >= today() - 1 AND hour < today()
GROUP BY day, endpoint_group
ORDER BY requests DESC
LIMIT 10;

-- Проверка
SELECT name, engine FROM system.tables
WHERE database = 'pulse' AND (engine = 'MaterializedView' OR name LIKE '%hourly%' OR name LIKE 'retention%' OR name LIKE '%snapshot%' OR name LIKE 'top_%')
ORDER BY engine, name;

SELECT view, status, next_refresh_time FROM system.view_refreshes WHERE database = 'pulse';
