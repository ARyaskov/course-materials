-- Pulse: векторный поиск (глава 16). Требует ddl/vectors.sql, ingestion/build_embeddings.sql, SYSTEM REFRESH VIEW mv_user_behavior_vectors.

-- ===== 1. Здоровье колонок векторов =====
SELECT 'messages' AS t, count() AS rows, uniqExact(length(embedding)) AS dims, round(avg(L2Norm(embedding)), 3) AS avg_norm
FROM pulse.message_embeddings
UNION ALL
SELECT 'behavior', count(), uniqExact(length(vector)), round(avg(L2Norm(vector)), 3) FROM pulse.user_behavior_vectors FINAL;

-- ===== 2. Похожие сообщения на образец (полный перебор) =====
WITH (SELECT embedding FROM pulse.message_embeddings WHERE message LIKE 'upstream timeout%' LIMIT 1) AS q
SELECT service, message, occurrences, round(cosineDistance(embedding, q), 3) AS distance
FROM pulse.message_embeddings ORDER BY distance LIMIT 10;

-- Порог вместо LIMIT
WITH (SELECT embedding FROM pulse.message_embeddings WHERE message LIKE 'upstream timeout%' LIMIT 1) AS q
SELECT message, round(cosineDistance(embedding, q), 3) AS distance
FROM pulse.message_embeddings WHERE distance < 0.3 ORDER BY distance LIMIT 50;

-- Похожие на любой из нескольких образцов
WITH (SELECT groupArray(embedding) FROM pulse.message_embeddings
      WHERE message IN ('connection refused by database', 'payment provider unavailable')) AS qs
SELECT message, round(arrayMin(arrayMap(q -> cosineDistance(embedding, q), qs)), 3) AS distance
FROM pulse.message_embeddings ORDER BY distance LIMIT 10;

-- ===== 3. Кластеры сообщений и их сводка =====
SELECT c.cluster, count() AS messages, sum(m.occurrences) AS lines, any(m.message) AS sample
FROM pulse.message_clusters AS c JOIN pulse.message_embeddings AS m USING (message_hash)
GROUP BY c.cluster ORDER BY lines DESC;

-- Центроиды сервисов и расстояния между ними
SELECT a.service AS s1, b.service AS s2, round(cosineDistance(a.c, b.c), 3) AS distance
FROM (SELECT service, L2Normalize(avgForEach(embedding)) AS c FROM pulse.message_embeddings GROUP BY service) AS a
CROSS JOIN (SELECT service, L2Normalize(avgForEach(embedding)) AS c FROM pulse.message_embeddings GROUP BY service) AS b
WHERE a.service < b.service ORDER BY distance;

-- ===== 4. Похожие пользователи =====
WITH (SELECT vector FROM pulse.user_behavior_vectors FINAL WHERE user_id = 42) AS q
SELECT user_id, events, round(cosineDistance(vector, q), 4) AS distance
FROM pulse.user_behavior_vectors FINAL WHERE user_id != 42 ORDER BY distance LIMIT 20;

-- ===== 5. Похожие на купивших, но не купившие =====
WITH (
    SELECT L2Normalize(avgForEach(vector)) FROM pulse.user_behavior_vectors FINAL
    WHERE user_id IN (SELECT DISTINCT user_id FROM pulse.events WHERE event_type = 'purchase' AND event_date >= today() - 30)
) AS buyers_centroid
SELECT user_id, round(cosineDistance(vector, buyers_centroid), 4) AS distance
FROM pulse.user_behavior_vectors FINAL
WHERE user_id NOT IN (SELECT DISTINCT user_id FROM pulse.events WHERE event_type = 'purchase' AND event_date >= today() - 30)
ORDER BY distance LIMIT 100;

-- ===== 6. Сегменты поведения: инициализация, итерация (повторить 3 раза), описание, аномалии =====
TRUNCATE TABLE pulse.behavior_centroids;
INSERT INTO pulse.behavior_centroids
SELECT toUInt8(rowNumberInAllBlocks()), vector FROM pulse.user_behavior_vectors FINAL ORDER BY rand() LIMIT 8;

-- итерация: пересчёт (перед повтором — TRUNCATE и вставка результата предыдущей итерации)
SELECT cluster, L2Normalize(avgForEach(vector)) AS centroid
FROM (
    SELECT v.user_id, v.vector, argMin(c.cluster, cosineDistance(v.vector, c.centroid)) AS cluster
    FROM pulse.user_behavior_vectors AS v FINAL CROSS JOIN pulse.behavior_centroids AS c
    GROUP BY v.user_id, v.vector
)
GROUP BY cluster;

SELECT cluster, count() AS users, round(avg(vector[3]), 3) AS purchase_share, round(avg(vector[35]), 3) AS revenue_norm,
       arrayMap(h -> round(avg(vector[11 + h]), 3), range(24)) AS hour_profile
FROM (
    SELECT v.user_id, v.vector, argMin(c.cluster, cosineDistance(v.vector, c.centroid)) AS cluster
    FROM pulse.user_behavior_vectors AS v FINAL CROSS JOIN pulse.behavior_centroids AS c
    GROUP BY v.user_id, v.vector
)
GROUP BY cluster ORDER BY users DESC;

SELECT v.user_id, round(min(cosineDistance(v.vector, c.centroid)), 4) AS distance_to_nearest
FROM pulse.user_behavior_vectors AS v FINAL CROSS JOIN pulse.behavior_centroids AS c
GROUP BY v.user_id ORDER BY distance_to_nearest DESC LIMIT 20;

-- ===== 7. Полнота приближённого индекса (на копии таблицы с индексом) =====
-- WITH (SELECT embedding FROM pulse.message_embeddings_384 ORDER BY rand() LIMIT 1) AS q,
--      exact AS (SELECT message_hash FROM pulse.message_embeddings_384 ORDER BY cosineDistance(embedding, q) LIMIT 10 SETTINGS use_skip_indexes = 0),
--      approx AS (SELECT message_hash FROM pulse.message_embeddings_384 ORDER BY cosineDistance(embedding, q) LIMIT 10)
-- SELECT count() / 10 AS recall FROM approx WHERE message_hash IN exact;

-- ===== 8. Кластеры ошибок и затронутая выручка =====
SELECT c.cluster, uniq(l.user_id) AS affected_users, sum(e.amount) AS revenue_at_risk
FROM pulse.message_clusters AS c
JOIN pulse.app_logs AS l ON cityHash64(normalizeQuery(lower(l.message))) = c.message_hash
JOIN pulse.events AS e ON e.user_id = l.user_id AND e.event_type = 'purchase'
    AND e.event_time BETWEEN toDateTime(l.ts) AND toDateTime(l.ts) + INTERVAL 1 HOUR
WHERE l.ts >= now() - INTERVAL 1 DAY AND l.level = 'ERROR'
GROUP BY c.cluster ORDER BY revenue_at_risk DESC;
