# Мини-кластер Pulse (глава 13)

Два шарда × две реплики + один узел ClickHouse Keeper. Стенд независим от одиночного.

```text
                 keeper (9181)
        ┌──────────┴──────────┐
     shard 1                shard 2
 ch-s1-r1  ch-s1-r2      ch-s2-r1  ch-s2-r2
  :8124     :8125          :8126     :8127     (HTTP на хосте)
```

## Запуск

```bash
cd cluster
docker compose -f docker-compose.cluster.yml up -d

# реплицируемая база (единственный ON CLUSTER)
docker exec -i pulse-ch-s1-r1 clickhouse-client --user analyst --password analyst \
  --queries-file /dev/stdin < ../ddl/cluster/00_database.sql

# схема кластера — один раз на любом узле, DDL реплицируется базой
docker exec -i pulse-ch-s1-r1 clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ../ddl/cluster/01_tables.sql

# загрузка через распределённую таблицу
CLICKHOUSE_PORT=8124 PULSE_INSERT_TABLE=events_in_dist python ../ingestion/app/emit_events.py --rate 500 --seconds 60

# проверки
docker exec -i pulse-ch-s1-r1 clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ../queries/ch13_cluster.sql
```

## Конфигурация

- `config/common.xml` — кластер `pulse_cluster` (`internal_replication = true`, общий `secret`), адрес Keeper, очередь DDL.
- `config/ch-*.xml` — макросы `{shard}`/`{replica}` каждого узла.
- `config/keeper.xml` — Keeper (один узел; в продакшене — три).

## Сценарии отказов

| Действие | Ожидаемое поведение |
| --- | --- |
| `docker stop pulse-ch-s1-r2` | вставки и чтение работают; после `docker start` реплика догоняет (`system.replicas`: queue_size → 0) |
| `docker stop pulse-keeper` | таблицы в режиме только для чтения (`is_readonly = 1`), вставки отказывают, чтение работает; после старта Keeper всё восстанавливается само |
| остановка обоих узлов шарда | запросы через `_dist` отказывают (или частичный результат при `skip_unavailable_shards = 1`) |

Остановка стенда с удалением данных: `docker compose -f docker-compose.cluster.yml down -v`.
