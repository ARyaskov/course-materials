-- Pulse: объектное хранилище и озеро (глава 14).
-- Требует: docker-compose.s3.yml, config/config.d/storage.xml, ddl/storage_tiering.sql, ddl/named_collections.sql, ddl/lake.sql.

-- 1. Диски, политики, распределение кусков по дискам
SELECT name, type, formatReadableSize(free_space) AS free FROM system.disks;
SELECT policy_name, volume_name, disks FROM system.storage_policies;
SELECT partition, disk_name, count() AS parts, sum(rows) AS rows
FROM system.parts WHERE database = 'pulse' AND table = 'events' AND active
GROUP BY partition, disk_name ORDER BY partition;

-- 2. Переезды кусков в журнале
SELECT event_time, part_name, disk_name, duration_ms FROM system.part_log
WHERE database = 'pulse' AND table = 'events' AND event_type = 'MovePart' ORDER BY event_time DESC LIMIT 10;

-- 3. Чтение с холодного тома: дважды, сравнить обращения к хранилищу и кэш
SELECT country, count() AS events, uniq(user_id) AS users
FROM pulse.events
WHERE event_time >= now() - INTERVAL 60 DAY AND event_time < now() - INTERVAL 40 DAY
GROUP BY country;

SELECT query_duration_ms, read_rows,
       ProfileEvents['S3ReadRequestsCount'] AS s3_reads,
       ProfileEvents['CachedReadBufferReadFromCacheBytes'] AS from_cache_bytes,
       ProfileEvents['CachedReadBufferReadFromSourceBytes'] AS from_s3_bytes
FROM system.query_log
WHERE type = 'QueryFinish' AND query ILIKE '%INTERVAL 40 DAY%' AND event_date = today()
ORDER BY event_time DESC LIMIT 2;

-- 4. Состояние кэша файловой системы
SELECT cache_name, formatReadableSize(sum(size)) AS cached, count() AS segments
FROM system.filesystem_cache GROUP BY cache_name;

-- 5. Озеро: содержимое по месяцам и отсев по каталогу (сравнить S3ReadRequestsCount двух запросов)
SELECT month, count() AS events FROM pulse.lake_events GROUP BY month ORDER BY month SETTINGS use_hive_partitioning = 1;
SELECT count() FROM pulse.lake_events WHERE month = toString(toYYYYMM(now())) SETTINGS use_hive_partitioning = 1;
SELECT count() FROM pulse.lake_events SETTINGS use_hive_partitioning = 1;

SELECT substring(query, 1, 70) AS q, read_rows, ProfileEvents['S3ReadRequestsCount'] AS s3_reads
FROM system.query_log
WHERE type = 'QueryFinish' AND query ILIKE '%lake_events%' AND event_date = today()
ORDER BY event_time DESC LIMIT 3;

-- 6. Метаданные файла Parquet: группы строк и статистики (сортированный файл — узкие диапазоны)
SELECT num_rows, num_row_groups, row_groups[1].columns[1].statistics AS first_group_stats
FROM s3(minio_lake, filename = 'events/month=*/*.parquet', format = 'ParquetMetadata') LIMIT 1;

-- 7. Чтение архива по маске через функцию (без таблицы) и агрегат по истории
SELECT toDate(event_time) AS day, uniq(user_id) AS dau
FROM s3(minio_lake, filename = 'events/**/*.parquet', format = 'Parquet')
WHERE event_type = 'purchase'
GROUP BY day ORDER BY day
SETTINGS use_hive_partitioning = 1;

-- 8. Уплотнение мелких файлов: каталог -> один отсортированный файл
-- INSERT INTO FUNCTION s3(minio_lake, filename = 'events_compacted/month=202609/all.parquet', format = 'Parquet')
-- SELECT * FROM s3(minio_lake, filename = 'events_parts/month=202609/*.parquet', format = 'Parquet') ORDER BY event_time;

-- 9. Перелив месяца в кластер (если запущен cluster/): выполнять на узле кластера
-- INSERT INTO pulse.events_dist SELECT * EXCEPT (endpoint_group)
-- FROM remote('host.docker.internal:9010', pulse.events, 'analyst', 'analyst')
-- WHERE toYYYYMM(event_time) = 202609;
