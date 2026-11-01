-- Pulse: озеро данных — помесячные файлы Parquet в раскладке Hive (глава 14).
-- Требует ddl/named_collections.sql. Стратегия записи partition_strategy = 'hive' появилась в 25.x —
-- при отказе в вашей сборке используйте запись через функцию s3 с подстановкой {_partition_id} (см. ingestion/export_lake.sql).

CREATE TABLE IF NOT EXISTS pulse.lake_events
(
    event_time  DateTime,
    event_date  Date,
    received_at DateTime,
    user_id     UInt64,
    session_id  UUID,
    event_type  LowCardinality(String),
    country     LowCardinality(String),
    device      LowCardinality(String),
    endpoint    String,
    status      UInt16,
    amount      Nullable(Decimal(18, 2)),
    attributes  Map(String, String),
    plan        LowCardinality(String)
)
ENGINE = S3(minio_lake, filename = 'events', format = 'Parquet', partition_strategy = 'hive')
PARTITION BY toYYYYMM(event_time);

-- Чтение с отсевом по каталогу: виртуальная колонка month из пути
SELECT month, count() AS events
FROM pulse.lake_events
GROUP BY month
ORDER BY month
SETTINGS use_hive_partitioning = 1;
