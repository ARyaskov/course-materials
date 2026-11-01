-- Pulse: профили пользователей и история тарифов (глава 8).

-- Текущее состояние профиля: несколько версий по user_id, схлопываются при слиянии.
-- Читать через argMax(..., updated_at) или FINAL на маленьких выборках.
CREATE TABLE IF NOT EXISTS pulse.user_profiles
(
    user_id     UInt64,
    name        String,
    plan        LowCardinality(String),
    signup_date Date,
    updated_at  DateTime
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY user_id;

-- История тарифов с интервалами действия: valid_from включительно, valid_to исключительно.
-- Открытый интервал кодируется далёкой датой (нужно словарю RANGE_HASHED; ASOF JOIN использует только valid_from).
CREATE TABLE IF NOT EXISTS pulse.user_plan_history
(
    user_id    UInt64,
    valid_from DateTime,
    valid_to   DateTime DEFAULT toDateTime('2106-01-01 00:00:00'),
    plan       LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY (user_id, valid_from);
