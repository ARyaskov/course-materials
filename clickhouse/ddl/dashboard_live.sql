-- Pulse: витрина по минутам для живого дашборда (глава 19).
-- Панель читает витрину за закрытые минуты и события за последние 2–3 минуты одним запросом (queries/ch19_dashboard_api.sql).

CREATE TABLE IF NOT EXISTS pulse.events_by_minute
(
    minute         DateTime,
    event_type     LowCardinality(String),
    endpoint_group LowCardinality(String),
    events         UInt64,
    errors         UInt64,
    revenue        Decimal(18, 2)
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(minute)
ORDER BY (minute, event_type, endpoint_group)
TTL minute + INTERVAL 90 DAY;

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_events_by_minute TO pulse.events_by_minute AS
SELECT toStartOfMinute(event_time) AS minute, event_type, endpoint_group,
       count() AS events, countIf(status >= 500) AS errors, sum(ifNull(amount, 0)) AS revenue
FROM pulse.events
GROUP BY minute, event_type, endpoint_group;

CREATE TABLE IF NOT EXISTS pulse.events_by_minute_staging AS pulse.events_by_minute;

GRANT SELECT ON pulse.events_by_minute TO dashboard;

-- Сверка за последний закрытый час
WITH toStartOfHour(now()) - INTERVAL 1 HOUR AS h
SELECT (SELECT sum(events) FROM pulse.events_by_minute WHERE minute >= h AND minute < h + INTERVAL 1 HOUR) AS from_view,
       (SELECT count() FROM pulse.events WHERE event_time >= h AND event_time < h + INTERVAL 1 HOUR) AS from_events;
