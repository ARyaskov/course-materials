-- Pulse: мини-хранилище наблюдаемости (глава 15). Требует ddl/logs.sql (pulse.app_logs).
-- Логи: точка входа logs_in -> app_logs (не DEBUG) + app_logs_debug (выборка 10 % запросов); витрина по минутам.
-- Метрики: узкая таблица metrics + минутная витрина. Трассы: spans. Здоровье сервера: ch_health. Запросы: query_health_1m.

-- ===================== ЛОГИ =====================
ALTER TABLE pulse.app_logs ADD COLUMN IF NOT EXISTS host LowCardinality(String) DEFAULT '';

CREATE TABLE IF NOT EXISTS pulse.logs_in
(
    ts         DateTime64(3),
    service    LowCardinality(String),
    level      LowCardinality(String),
    host       LowCardinality(String) DEFAULT '',
    request_id UUID,
    user_id    UInt64,
    endpoint   LowCardinality(String),
    message    String,
    labels     Map(String, String)
)
ENGINE = Null;

CREATE TABLE IF NOT EXISTS pulse.app_logs_debug
(
    ts         DateTime64(3) CODEC(DoubleDelta, ZSTD(1)),
    service    LowCardinality(String),
    host       LowCardinality(String),
    request_id UUID,
    message    String CODEC(ZSTD(3))
)
ENGINE = MergeTree
PARTITION BY toDate(ts)
ORDER BY (service, ts)
TTL toDateTime(ts) + INTERVAL 2 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.mv_logs_main TO pulse.app_logs AS
SELECT ts, service, level, host, request_id, user_id, endpoint, substring(message, 1, 4096) AS message, labels
FROM pulse.logs_in
WHERE level != 'DEBUG';

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.mv_logs_debug TO pulse.app_logs_debug AS
SELECT ts, service, host, request_id, substring(message, 1, 4096) AS message
FROM pulse.logs_in
WHERE level = 'DEBUG' AND cityHash64(request_id) % 10 = 0;

CREATE TABLE IF NOT EXISTS pulse.logs_by_minute
(
    minute  DateTime,
    service LowCardinality(String),
    level   LowCardinality(String),
    lines   UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(minute)
ORDER BY (minute, service, level)
TTL minute + INTERVAL 1 YEAR;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.mv_logs_by_minute TO pulse.logs_by_minute AS
SELECT toStartOfMinute(ts) AS minute, service, level, count() AS lines
FROM pulse.app_logs
GROUP BY minute, service, level;

-- ===================== МЕТРИКИ =====================
CREATE TABLE IF NOT EXISTS pulse.metrics
(
    metric    LowCardinality(String),
    labels    Map(LowCardinality(String), String),
    series_id UInt64 MATERIALIZED cityHash64(metric, labels),
    ts        DateTime CODEC(DoubleDelta, ZSTD(1)),
    value     Float64 CODEC(Gorilla, ZSTD(1))
)
ENGINE = MergeTree
PARTITION BY toDate(ts)
ORDER BY (metric, series_id, ts)
TTL ts + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS pulse.metrics_1m
(
    metric    LowCardinality(String),
    series_id UInt64,
    labels    Map(LowCardinality(String), String),
    minute    DateTime,
    avg_v     AggregateFunction(avg, Float64),
    min_v     SimpleAggregateFunction(min, Float64),
    max_v     SimpleAggregateFunction(max, Float64),
    last_v    SimpleAggregateFunction(anyLast, Float64),
    quant     AggregateFunction(quantilesTDigest(0.5, 0.95, 0.99), Float64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(minute)
ORDER BY (metric, series_id, minute)
TTL minute + INTERVAL 1 YEAR;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.mv_metrics_1m TO pulse.metrics_1m AS
SELECT metric, series_id, any(labels) AS labels, toStartOfMinute(ts) AS minute,
       avgState(value) AS avg_v, min(value) AS min_v, max(value) AS max_v, anyLast(value) AS last_v,
       quantilesTDigestState(0.5, 0.95, 0.99)(value) AS quant
FROM pulse.metrics
GROUP BY metric, series_id, minute;

-- ===================== ТРАССЫ =====================
CREATE TABLE IF NOT EXISTS pulse.spans
(
    trace_id       UUID,
    span_id        UInt64,
    parent_span_id UInt64,
    request_id     UUID,
    service        LowCardinality(String),
    operation      LowCardinality(String),
    start_ts       DateTime64(6) CODEC(DoubleDelta, ZSTD(1)),
    duration_us    UInt64,
    status         LowCardinality(String),
    attributes     Map(LowCardinality(String), String),
    INDEX idx_trace   trace_id   TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_request request_id TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toDate(start_ts)
ORDER BY (service, operation, start_ts)
TTL toDateTime(start_ts) + INTERVAL 7 DAY;

-- ===================== ЗДОРОВЬЕ СЕРВЕРА =====================
CREATE TABLE IF NOT EXISTS pulse.ch_health
(
    ts     DateTime,
    metric LowCardinality(String),
    value  Float64
)
ENGINE = MergeTree
ORDER BY (metric, ts)
TTL ts + INTERVAL 90 DAY;

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_ch_health
REFRESH EVERY 1 MINUTE
APPEND TO pulse.ch_health AS
SELECT now() AS ts, metric, value FROM system.metrics
WHERE metric IN ('Query', 'Merge', 'PartMutation', 'MemoryTracking', 'TCPConnection', 'HTTPConnection', 'ReadonlyReplica')
UNION ALL
SELECT now(), metric, value FROM system.asynchronous_metrics
WHERE metric IN ('MaxPartCountForPartition', 'OSMemoryAvailable', 'ReplicasMaxAbsoluteDelay', 'ReplicasMaxQueueSize')
   OR metric LIKE 'DiskAvailable_%'
UNION ALL
SELECT now(), event, value FROM system.events
WHERE event IN ('Query', 'FailedQuery', 'InsertedRows', 'DelayedInserts', 'RejectedInserts', 'QueryMemoryLimitExceeded');

-- ===================== МОНИТОРИНГ ЗАПРОСОВ =====================
CREATE TABLE IF NOT EXISTS pulse.query_health_1m
(
    minute     DateTime,
    panel      LowCardinality(String),
    user       LowCardinality(String),
    runs       UInt64,
    failed     UInt64,
    p95_ms     Float64,
    read_rows  UInt64,
    max_memory UInt64
)
ENGINE = MergeTree
ORDER BY (panel, minute)
TTL minute + INTERVAL 1 YEAR;

CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_query_health_1m
REFRESH EVERY 1 MINUTE
APPEND TO pulse.query_health_1m AS
SELECT toStartOfMinute(event_time) AS minute,
       if(log_comment = '', 'other', log_comment) AS panel, user,
       countIf(type = 'QueryFinish') AS runs,
       countIf(type LIKE 'Exception%') AS failed,
       quantile(0.95)(query_duration_ms) AS p95_ms,
       sum(read_rows) AS read_rows,
       max(memory_usage) AS max_memory
FROM system.query_log
WHERE event_time >= now() - INTERVAL 2 MINUTE AND event_time < toStartOfMinute(now())
  AND type != 'QueryStart' AND query_kind IN ('Select', 'Insert')
GROUP BY minute, panel, user;

-- Классы нагрузки (25.x; при отказе в сборке — пропустить)
-- CREATE RESOURCE IF NOT EXISTS cpu (MASTER THREAD, WORKER THREAD);
-- CREATE WORKLOAD IF NOT EXISTS all;
-- CREATE WORKLOAD IF NOT EXISTS dashboard IN all SETTINGS weight = 3;
-- CREATE WORKLOAD IF NOT EXISTS analysts IN all SETTINGS weight = 1;

SELECT name, engine FROM system.tables
WHERE database = 'pulse' AND (name LIKE '%logs%' OR name LIKE 'metrics%' OR name IN ('spans', 'ch_health', 'query_health_1m'))
ORDER BY name;
