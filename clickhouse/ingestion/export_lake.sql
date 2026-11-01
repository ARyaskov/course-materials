-- Pulse: выгрузка месяца событий в озеро (глава 14). Замените 202609 на нужный месяц.

-- Вариант 1: через таблицу озера с раскладкой Hive (ddl/lake.sql)
INSERT INTO pulse.lake_events
SELECT * EXCEPT (endpoint_group)
FROM pulse.events
WHERE toYYYYMM(event_time) = 202609
ORDER BY event_time
SETTINGS output_format_parquet_compression_method = 'zstd',
         output_format_parquet_row_group_size = 500000;

-- Вариант 2 (старые сборки без partition_strategy): функция s3 с подстановкой партиции в путь
-- INSERT INTO FUNCTION s3(minio_lake, filename = 'events/month={_partition_id}/part-{_partition_id}.parquet', format = 'Parquet')
-- PARTITION BY toYYYYMM(event_time)
-- SELECT * EXCEPT (endpoint_group) FROM pulse.events WHERE toYYYYMM(event_time) = 202609 ORDER BY event_time
-- SETTINGS output_format_parquet_compression_method = 'zstd', output_format_parquet_row_group_size = 500000;

-- Сверка: строки в озере за месяц против таблицы
SELECT
    (SELECT count() FROM pulse.lake_events WHERE month = '202609' SETTINGS use_hive_partitioning = 1) AS in_lake,
    (SELECT count() FROM pulse.events WHERE toYYYYMM(event_time) = 202609)                             AS in_table;
