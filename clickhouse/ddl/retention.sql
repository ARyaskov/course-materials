-- Pulse: партиционирование и TTL для слоёв данных (глава 5).

-- Сырьё: партиции по дню, живёт 3 дня
CREATE OR REPLACE TABLE pulse.raw_events
(
    received_at DateTime DEFAULT now(),
    payload     String
)
ENGINE = MergeTree
PARTITION BY toDate(received_at)
ORDER BY received_at
TTL received_at + INTERVAL 3 DAY;

-- Чистые события: партиции по месяцу, живут 90 дней
CREATE OR REPLACE TABLE pulse.events
(
    event_time DateTime CODEC(DoubleDelta, ZSTD(1)),
    event_date Date DEFAULT toDate(event_time),
    user_id    UInt64,
    session_id UUID,
    event_type LowCardinality(String),
    country    LowCardinality(String) DEFAULT '',
    device     LowCardinality(String) DEFAULT '',
    endpoint   String DEFAULT '',
    status     UInt16 DEFAULT 0,
    amount     Nullable(Decimal(18, 2)),
    attributes Map(String, String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, event_type, user_id)
TTL event_time + INTERVAL 90 DAY;

-- Проверка распределения по партициям
SELECT partition,
       sum(rows)                              AS rows,
       formatReadableSize(sum(bytes_on_disk)) AS size,
       min(min_time)                          AS from_time,
       max(max_time)                          AS to_time
FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active
GROUP BY partition
ORDER BY partition;
