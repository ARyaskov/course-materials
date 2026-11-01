# Загрузка событий в Pulse

Конвейер главы 6. Три входа, один чистый слой.

```text
 Kafka ──▶ events_kafka ──▶ raw_events ──▶ raw_to_events_mv ──▶ events ──▶ архив (Parquet)
 приложение ──▶ events_in ──▶ events_in_to_events_mv ──────────▶ events
 файлы ──▶ file() + ingest_files ───────────────────────────────▶ events
 переразбор: raw_events ──▶ events_staging ──▶ REPLACE PARTITION ──▶ events
```

## Порядок запуска

```bash
# 1. Стенд с брокером
docker compose -f docker-compose.yml -f docker-compose.kafka.yml up -d
docker exec -it pulse-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --create --topic pulse.events --partitions 2

# 2. Схема хранения и конвейер
docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ddl/retention.sql
docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ddl/ingestion.sql

# 3. Симулятор приложения (типизированные вставки в events_in)
pip install -r ingestion/app/requirements.txt
python ingestion/app/emit_events.py --rate 500 --seconds 60

# 3a. Тот же симулятор через брокер
pip install confluent-kafka
python ingestion/app/emit_events.py --rate 500 --seconds 60 --kafka

# 4. Файлы из ingestion/files (идемпотентно, с ведомостью ingest_files)
docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ingestion/load_files.sql
```

## Файлы

- `app/emit_events.py` — буфер с двумя порогами, токен идемпотентности, ретраи, сброс на диск в `app/spill/`.
- `files/` — примонтировано в контейнер как `/var/lib/clickhouse/user_files/pulse`; доступно через `file('pulse/...')`.
- `load_files.sql` — обзор, загрузка новых файлов, запись в ведомость.
- `export_month.sql` — выгрузка месяца в Parquet (см. комментарий в файле про перенаправление вывода клиента).
- `generate_events.sql` — генератор синтетики из главы 2 (миллион событий одним `INSERT ... SELECT`).

## Проверки

```sql
-- Пакеты, а не строки
SELECT count() AS inserts, sum(written_rows) AS rows, round(avg(written_rows)) AS avg_batch
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind = 'Insert' AND event_time >= now() - INTERVAL 5 MINUTE;

-- Куски в норме
SELECT count() AS active_parts, sum(rows) AS rows FROM system.parts
WHERE database = 'pulse' AND table = 'events' AND active;

-- Задержка доставки через брокер
SELECT quantiles(0.5, 0.95, 0.99)(received_at - event_time) FROM pulse.raw_parsed
WHERE received_at >= now() - INTERVAL 10 MINUTE;

-- Потребители Kafka
SELECT table, num_messages_read, last_poll_time, num_commits, exceptions.text
FROM system.kafka_consumers WHERE database = 'pulse';
```

Тестовый файл `files/events_sample.jsonl` содержит события за август 2026 года; если стенд запускается позже, чем через 90 дней после этой даты, строки попадут под TTL таблицы `events` при следующем слиянии — для свежих данных используйте симулятор.
