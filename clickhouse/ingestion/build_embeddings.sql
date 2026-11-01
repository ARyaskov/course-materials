-- Pulse: учебные векторы сообщений по хешированным триграммам (глава 16). Не требует модели.
-- Числа и литералы в сообщениях заменяются заполнителями (normalizeQuery), чтобы варианты одного шаблона совпали.

INSERT INTO pulse.message_embeddings (message_hash, service, message, first_seen, occurrences, embedding)
WITH 128 AS dim
SELECT cityHash64(msg) AS message_hash, service, msg AS message, min(ts) AS first_seen, count() AS occurrences,
       L2Normalize(arrayMap(i -> toFloat32(countEqual(hashed, i)), range(dim))) AS embedding
FROM (
    SELECT service, ts, normalizeQuery(lower(message)) AS msg,
           arrayMap(g -> toUInt32(cityHash64(g) % dim), ngrams(msg, 3)) AS hashed
    FROM pulse.app_logs
    WHERE ts >= now() - INTERVAL 3 DAY
)
GROUP BY service, msg, hashed;

-- Здоровье колонки
SELECT count() AS messages, uniqExact(length(embedding)) AS dims, round(avg(L2Norm(embedding)), 3) AS avg_norm,
       countIf(arrayExists(x -> isNaN(x), embedding)) AS with_nan
FROM pulse.message_embeddings;

-- Центроиды сообщений: инициализация 8 случайными и три итерации (повторить блок итерации 3 раза)
TRUNCATE TABLE pulse.message_centroids;
INSERT INTO pulse.message_centroids
SELECT toUInt8(rowNumberInAllBlocks()) AS cluster, embedding FROM pulse.message_embeddings ORDER BY rand() LIMIT 8;

-- итерация:
INSERT INTO pulse.message_centroids
SELECT cluster, L2Normalize(avgForEach(embedding))
FROM (
    SELECT m.message_hash, m.embedding, argMin(c.cluster, cosineDistance(m.embedding, c.centroid)) AS cluster
    FROM pulse.message_embeddings AS m CROSS JOIN pulse.message_centroids AS c
    GROUP BY m.message_hash, m.embedding
)
GROUP BY cluster;
-- (таблица центроидов на MergeTree накапливает версии; читать последнюю через argMax по времени вставки
--  или очищать перед каждой итерацией — в учебном сценарии достаточно TRUNCATE + повтор)

-- Назначение кластеров
INSERT INTO pulse.message_clusters
SELECT m.message_hash, argMin(c.cluster, cosineDistance(m.embedding, c.centroid)) AS cluster
FROM pulse.message_embeddings AS m CROSS JOIN pulse.message_centroids AS c
GROUP BY m.message_hash;
