-- Pulse: продуманная типизированная таблица событий (глава 3).
-- Заменяет упрощённую версию из главы 2.
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
ORDER BY (event_time, event_type, user_id);
