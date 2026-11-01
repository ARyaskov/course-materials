-- Pulse: логи приложения с текстовым индексом (глава 9; используется в главе 15).
-- Текстовый индекс в некоторых сборках 25.x требует включения экспериментальной возможности.
-- Если CREATE TABLE отказывает, раскомментируйте строку ниже (имя настройки — по документации вашей версии):
-- SET allow_experimental_full_text_index = 1;

CREATE TABLE IF NOT EXISTS pulse.app_logs
(
    ts         DateTime64(3),
    service    LowCardinality(String),
    level      LowCardinality(String),
    request_id UUID,
    user_id    UInt64,
    endpoint   LowCardinality(String),
    message    String,
    labels     Map(String, String),
    INDEX idx_request request_id      TYPE bloom_filter(0.01) GRANULARITY 1,   -- все строки одного запроса
    INDEX idx_user    user_id         TYPE bloom_filter(0.01) GRANULARITY 2,   -- история пользователя
    INDEX idx_labels  mapKeys(labels) TYPE bloom_filter(0.01) GRANULARITY 4,   -- редкие метки (canary и т. п.)
    INDEX idx_message lower(message)  TYPE text(tokenizer = 'default') GRANULARITY 1   -- поиск по словам
)
ENGINE = MergeTree
PARTITION BY toDate(ts)
ORDER BY (service, level, ts)
TTL toDateTime(ts) + INTERVAL 14 DAY;

SELECT name, type, expr FROM system.data_skipping_indices
WHERE database = 'pulse' AND table = 'app_logs';
