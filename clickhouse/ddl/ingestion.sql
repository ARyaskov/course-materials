-- Pulse: конвейер загрузки (глава 6).
-- Предполагает, что уже применён ddl/retention.sql (таблицы pulse.raw_events и pulse.events).
-- Применение:
--   docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
--     --database pulse --queries-file /dev/stdin < ddl/ingestion.sql

-- 1. Защита от повторных блоков при ретраях (на нереплицируемой таблице выключена по умолчанию)
ALTER TABLE pulse.events MODIFY SETTING non_replicated_deduplication_window = 1000;

-- 2. Профиль настроек для учётной записи загрузчика
CREATE SETTINGS PROFILE IF NOT EXISTS ingest_profile SETTINGS
    async_insert = 1,
    wait_for_async_insert = 1,
    input_format_skip_unknown_fields = 1,
    date_time_input_format = 'best_effort';

-- 3. Поток из Kafka: сообщения целиком, без разбора, в сырой слой
CREATE TABLE IF NOT EXISTS pulse.events_kafka
(
    payload String
)
ENGINE = Kafka
SETTINGS kafka_broker_list = 'kafka:29092',
         kafka_topic_list = 'pulse.events',
         kafka_group_name = 'clickhouse-pulse',
         kafka_format = 'JSONAsString',
         kafka_num_consumers = 1,
         kafka_handle_error_mode = 'stream';

CREATE TABLE IF NOT EXISTS pulse.events_kafka_errors
(
    received_at DateTime DEFAULT now(),
    raw_message String,
    error       String
)
ENGINE = MergeTree
ORDER BY received_at
TTL received_at + INTERVAL 7 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.events_kafka_mv TO pulse.raw_events AS
SELECT payload
FROM pulse.events_kafka
WHERE length(_error) = 0;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.events_kafka_errors_mv TO pulse.events_kafka_errors AS
SELECT _raw_message AS raw_message, _error AS error
FROM pulse.events_kafka
WHERE length(_error) > 0;

-- 4. Разбор сырья в чистый слой.
--    raw_parsed — обычное представление для пакетного переразбора и проверок;
--    raw_to_events_mv — материализованное, срабатывает на каждую вставку в raw_events.
--    Выражение разбора в них должно совпадать.
CREATE VIEW IF NOT EXISTS pulse.raw_parsed AS
SELECT
    received_at,
    parseDateTimeBestEffort(JSONExtractString(payload, 'event_time')) AS event_time,
    JSONExtractUInt(payload, 'user_id')                               AS user_id,
    toUUIDOrZero(JSONExtractString(payload, 'session_id'))            AS session_id,
    JSONExtractString(payload, 'event_type')                          AS event_type,
    JSONExtractString(payload, 'country')                             AS country,
    JSONExtractString(payload, 'device')                              AS device,
    JSONExtractString(payload, 'endpoint')                            AS endpoint,
    JSONExtractUInt(payload, 'status')                                AS status,
    toDecimal64OrNull(JSONExtractString(payload, 'amount'), 2)        AS amount,
    JSONExtract(payload, 'attributes', 'Map(String, String)')         AS attributes
FROM pulse.raw_events
WHERE JSONHas(payload, 'user_id') AND JSONHas(payload, 'event_time');

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.raw_to_events_mv TO pulse.events AS
SELECT
    parseDateTimeBestEffort(JSONExtractString(payload, 'event_time')) AS event_time,
    JSONExtractUInt(payload, 'user_id')                               AS user_id,
    toUUIDOrZero(JSONExtractString(payload, 'session_id'))            AS session_id,
    JSONExtractString(payload, 'event_type')                          AS event_type,
    JSONExtractString(payload, 'country')                             AS country,
    JSONExtractString(payload, 'device')                              AS device,
    JSONExtractString(payload, 'endpoint')                            AS endpoint,
    JSONExtractUInt(payload, 'status')                                AS status,
    toDecimal64OrNull(JSONExtractString(payload, 'amount'), 2)        AS amount,
    JSONExtract(payload, 'attributes', 'Map(String, String)')         AS attributes
FROM pulse.raw_events
WHERE JSONHas(payload, 'user_id') AND JSONHas(payload, 'event_time');

-- 5. Точка входа для доверенных типизированных вставок приложения (ничего не хранит)
CREATE TABLE IF NOT EXISTS pulse.events_in AS pulse.events ENGINE = Null;

CREATE MATERIALIZED VIEW IF NOT EXISTS pulse.events_in_to_events_mv TO pulse.events AS
SELECT * FROM pulse.events_in;

-- 6. Ведомость загруженных файлов и состояние пакетных шагов
CREATE TABLE IF NOT EXISTS pulse.ingest_files
(
    file_name String,
    rows      UInt64,
    loaded_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY file_name;

CREATE TABLE IF NOT EXISTS pulse.ingest_state
(
    step       String,
    watermark  DateTime,
    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY step;

-- 7. Staging той же структуры для переразбора и атомарной замены партиций
CREATE TABLE IF NOT EXISTS pulse.events_staging AS pulse.events;

-- Проверка: все объекты конвейера на месте
SELECT name, engine
FROM system.tables
WHERE database = 'pulse' AND (name LIKE '%events%' OR name LIKE 'ingest_%' OR name = 'raw_parsed')
ORDER BY name;
