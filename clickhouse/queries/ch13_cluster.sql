-- Pulse: проверки мини-кластера (глава 13). Выполнять на любом узле кластера.

-- 1. Топология и макросы
SELECT cluster, shard_num, replica_num, host_name, port FROM system.clusters WHERE cluster = 'pulse_cluster';
SELECT hostName() AS host, macro, substitution FROM clusterAllReplicas('pulse_cluster', system.macros) ORDER BY host, macro;

-- 2. Реплики: режим, отставание, очереди
SELECT hostName() AS host, table, is_readonly, absolute_delay, queue_size, inserts_in_queue, merges_in_queue,
       log_max_index - log_pointer AS log_lag, active_replicas, total_replicas
FROM clusterAllReplicas('pulse_cluster', system.replicas)
WHERE database = 'pulse' ORDER BY table, host;

-- 3. Застрявшие операции репликации
SELECT hostName() AS host, table, type, num_tries, last_exception, create_time
FROM clusterAllReplicas('pulse_cluster', system.replication_queue)
WHERE database = 'pulse' AND last_exception != '' ORDER BY create_time;

-- 4. Распределение данных по узлам (реплики шарда равны, шарды близки, пользователи не пересекаются)
SELECT hostName() AS host, count() AS events, uniq(user_id) AS users, min(event_time) AS from_time, max(event_time) AS to_time
FROM clusterAllReplicas('pulse_cluster', pulse.events)
GROUP BY host ORDER BY host;

SELECT count() AS total_via_dist FROM pulse.events_dist;

-- 5. Локальность: один пользователь — один шард
SELECT hostName() AS host, count() AS events FROM clusterAllReplicas('pulse_cluster', pulse.events)
WHERE user_id = 42 GROUP BY host;

-- 6. Пропуск шардов по ключу шардирования
EXPLAIN
SELECT count() FROM pulse.events_dist WHERE user_id = 42
SETTINGS optimize_skip_unused_shards = 1;

-- 7. Витрина по всему кластеру (состояния объединяются между шардами) и сверка с событиями
SELECT toStartOfHour(hour) AS h, uniqCombinedMerge(users) AS users, sum(events) AS events
FROM pulse.events_hourly_users_dist
WHERE hour >= now() - INTERVAL 2 HOUR GROUP BY h ORDER BY h;

SELECT toStartOfHour(event_time) AS h, uniqCombined(user_id) AS users, count() AS events
FROM pulse.events_dist
WHERE event_time >= now() - INTERVAL 2 HOUR GROUP BY h ORDER BY h;

-- 8. Очередь асинхронных вставок распределённых таблиц (норма: пусто)
SELECT hostName() AS host, table, data_files, formatReadableSize(data_compressed_bytes) AS pending, last_exception
FROM clusterAllReplicas('pulse_cluster', system.distribution_queue)
WHERE database = 'pulse';

-- 9. Части одного распределённого запроса на шардах (какой шард дольше)
SELECT initial_query_id, hostName() AS host, query_duration_ms, read_rows
FROM clusterAllReplicas('pulse_cluster', system.query_log)
WHERE type = 'QueryFinish' AND event_time >= now() - INTERVAL 10 MINUTE AND is_initial_query = 0
ORDER BY initial_query_id, host LIMIT 20;

-- 10. Куски и место по узлам
SELECT hostName() AS host, table, count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS size
FROM clusterAllReplicas('pulse_cluster', system.parts)
WHERE database = 'pulse' AND active GROUP BY host, table ORDER BY host, table;

-- 11. Журнал распределённых DDL (для ON CLUSTER; в Replicated-базе используется редко)
SELECT entry, host, status, exception_text FROM system.distributed_ddl_queue ORDER BY entry DESC LIMIT 10;

-- 12. Дерево координатора для таблицы событий первого шарда
SELECT name, value FROM system.zookeeper WHERE path = '/clickhouse/databases/pulse' LIMIT 20;
