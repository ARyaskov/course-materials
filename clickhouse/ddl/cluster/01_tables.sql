-- Pulse: схема кластера (глава 13). Выполняется ОДИН РАЗ на ЛЮБОМ узле в базе pulse (движок Replicated),
-- без ON CLUSTER — DDL реплицируется журналом базы.
-- Локальные таблицы сохраняют имена одиночного стенда; распределённые получают суффикс _dist.
-- Ключ шардирования всех таблиц с пользователем — cityHash64(user_id): события пользователя на одном шарде.

-- ===== Локальные реплицируемые таблицы (аргументы пути и реплики подставляет база) =====
CREATE TABLE IF NOT EXISTS pulse.raw_events
(
    received_at DateTime DEFAULT now(),
    payload     String
)
ENGINE = ReplicatedMergeTree
PARTITION BY toDate(received_at)
ORDER BY received_at
TTL received_at + INTERVAL 3 DAY;

CREATE TABLE IF NOT EXISTS pulse.events
(
    event_time  DateTime CODEC(DoubleDelta, ZSTD(1)),
    event_date  Date DEFAULT toDate(event_time),
    received_at DateTime DEFAULT now(),
    user_id     UInt64,
    session_id  UUID,
    event_type  LowCardinality(String),
    country     LowCardinality(String) DEFAULT '',
    device      LowCardinality(String) DEFAULT '',
    endpoint    String DEFAULT '',
    endpoint_group LowCardinality(String) MATERIALIZED replaceRegexpAll(endpoint, '/\\d+', '/{id}'),
    status      UInt16 DEFAULT 0,
    amount      Nullable(Decimal(18, 2)),
    attributes  Map(String, String),
    INDEX idx_session session_id TYPE bloom_filter(0.01) GRANULARITY 2
)
ENGINE = ReplicatedMergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, event_type, user_id)
TTL event_time + INTERVAL 90 DAY;

-- Точка входа для типизированных вставок (ничего не хранит; данные локальны по определению)
CREATE TABLE IF NOT EXISTS pulse.events_in AS pulse.events ENGINE = Null;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.events_in_to_events_mv TO pulse.events AS
SELECT * FROM pulse.events_in;

-- Витрина состояний по часам и странам (наполняется локально на каждом шарде)
CREATE TABLE IF NOT EXISTS pulse.events_hourly_users
(
    hour     DateTime,
    country  LowCardinality(String),
    users    AggregateFunction(uniqCombined, UInt64),
    buyers   AggregateFunction(uniqCombined, UInt64),
    events   SimpleAggregateFunction(sum, UInt64),
    revenue  SimpleAggregateFunction(sum, Decimal(18, 2))
)
ENGINE = ReplicatedAggregatingMergeTree
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, country);

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.mv_events_hourly_users TO pulse.events_hourly_users AS
SELECT toStartOfHour(event_time) AS hour, country,
       uniqCombinedState(user_id) AS users,
       uniqCombinedIfState(user_id, event_type = 'purchase') AS buyers,
       count() AS events,
       sum(ifNull(amount, 0)) AS revenue
FROM pulse.events
GROUP BY hour, country;

CREATE TABLE IF NOT EXISTS pulse.user_profiles
(
    user_id     UInt64,
    name        String,
    plan        LowCardinality(String),
    signup_date Date,
    updated_at  DateTime
)
ENGINE = ReplicatedReplacingMergeTree(updated_at)
ORDER BY user_id;

-- ===== Распределённые таблицы =====
CREATE TABLE IF NOT EXISTS pulse.events_dist AS pulse.events
ENGINE = Distributed(pulse_cluster, pulse, events, cityHash64(user_id));

CREATE TABLE IF NOT EXISTS pulse.events_in_dist AS pulse.events_in
ENGINE = Distributed(pulse_cluster, pulse, events_in, cityHash64(user_id));

CREATE TABLE IF NOT EXISTS pulse.raw_events_dist AS pulse.raw_events
ENGINE = Distributed(pulse_cluster, pulse, raw_events, rand());

CREATE TABLE IF NOT EXISTS pulse.events_hourly_users_dist AS pulse.events_hourly_users
ENGINE = Distributed(pulse_cluster, pulse, events_hourly_users);

CREATE TABLE IF NOT EXISTS pulse.user_profiles_dist AS pulse.user_profiles
ENGINE = Distributed(pulse_cluster, pulse, user_profiles, cityHash64(user_id));

-- Проверка: таблицы на всех узлах, пути реплик подставлены автоматически
SELECT hostName() AS host, table, replica_path, replica_name
FROM clusterAllReplicas('pulse_cluster', system.replicas)
WHERE database = 'pulse'
ORDER BY table, host;
