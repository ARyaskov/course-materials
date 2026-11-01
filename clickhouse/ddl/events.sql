-- Pulse: базовая таблица событий (глава 2).
-- Типы намеренно простые; продуманные типы — в главе 3.
CREATE OR REPLACE TABLE pulse.events
(
    event_time DateTime,
    user_id    UInt64,
    event_type String,
    country    String,
    endpoint   String
)
ENGINE = MergeTree
ORDER BY (event_time, user_id);
