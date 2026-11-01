-- Pulse: векторы сообщений и поведения (глава 16).
-- Учебные векторы сообщений — 128 измерений (хешированные триграммы, ingestion/build_embeddings.sql);
-- настоящие эмбеддинги — 384 измерения (ingestion/embed_messages.py) в отдельной таблице.
-- Векторы поведения — 40 признаков из событий, пересчёт раз в сутки обновляемым представлением.

-- ===== Сообщения =====
CREATE TABLE IF NOT EXISTS pulse.message_embeddings
(
    message_hash UInt64,
    service      LowCardinality(String),
    message      String,
    first_seen   SimpleAggregateFunction(min, DateTime),
    occurrences  SimpleAggregateFunction(sum, UInt64),
    embedding    Array(Float32),
    CONSTRAINT dim CHECK length(embedding) = 128
)
ENGINE = AggregatingMergeTree
ORDER BY (service, message_hash);

CREATE TABLE IF NOT EXISTS pulse.message_embeddings_384
(
    message_hash UInt64,
    service      LowCardinality(String),
    message      String,
    embedding    Array(Float32),
    CONSTRAINT dim CHECK length(embedding) = 384
)
ENGINE = ReplacingMergeTree
ORDER BY (service, message_hash);

CREATE TABLE IF NOT EXISTS pulse.message_centroids (cluster UInt8, centroid Array(Float32))
ENGINE = MergeTree ORDER BY cluster;

CREATE TABLE IF NOT EXISTS pulse.message_clusters (message_hash UInt64, cluster UInt8)
ENGINE = ReplacingMergeTree ORDER BY message_hash;

-- ===== Поведение пользователей =====
CREATE TABLE IF NOT EXISTS pulse.user_behavior_vectors
(
    user_id     UInt64,
    computed_at DateTime,
    events      UInt32,
    vector      Array(Float32),
    CONSTRAINT dim CHECK length(vector) = 40
)
ENGINE = ReplacingMergeTree(computed_at)
ORDER BY user_id;

-- Признаки (40): 4 доли типов | 6 долей групп endpoint-ов | 24 доли часов | сессии, ср. длина сессии, ср. пауза,
-- покупки, выручка, дни активности (все нормированы в [0, 1])
CREATE OR REPLACE MATERIALIZED VIEW pulse.mv_user_behavior_vectors
REFRESH EVERY 1 DAY OFFSET 3 HOUR
TO pulse.user_behavior_vectors AS
SELECT user_id, now() AS computed_at, count() AS events,
       arraySort(groupArray(event_time)) AS times,
       arraySplit((t, d) -> d > 1800, times, arrayDifference(times)) AS sessions,
       arrayConcat(
           arrayMap(t -> countIf(event_type = t) / count(), ['view', 'click', 'purchase', 'error']),
           arrayMap(g -> countIf(endpoint_group = g) / count(),
                    ['/home', '/pricing', '/checkout', '/api/v1/orders', '/api/v1/orders/{id}', '/api/v1/users/{id}']),
           arrayMap(h -> countIf(toHour(event_time) = h) / count(), range(24)),
           [least(length(sessions) / 100, 1),
            least(arrayAvg(arrayMap(s -> s[-1] - s[1], sessions)) / 3600, 1),
            least(arrayAvg(arrayDifference(times)) / 3600, 1),
            least(countIf(event_type = 'purchase') / 20, 1),
            least(sum(ifNull(amount, 0)) / 1000, 1),
            uniq(event_date) / 30]
       ) AS vector
FROM pulse.events
WHERE event_date >= today() - 30
GROUP BY user_id;

CREATE TABLE IF NOT EXISTS pulse.behavior_centroids (cluster UInt8, centroid Array(Float32))
ENGINE = MergeTree ORDER BY cluster;

-- Индекс векторного сходства (только для больших таблиц; статус в сборке проверить):
-- SET allow_experimental_vector_similarity_index = 1;
-- ALTER TABLE pulse.message_embeddings_384 ADD INDEX idx_vec embedding
--     TYPE vector_similarity('hnsw', 'cosineDistance', 384) GRANULARITY 100000000;
-- Измерение на стенде (1 млн строк-копий): время перебора vs индекса, полнота (queries/ch16_vectors.sql, блок 7).

SELECT name, engine FROM system.tables WHERE database = 'pulse'
  AND (name LIKE 'message_%' OR name LIKE '%behavior%') ORDER BY name;
