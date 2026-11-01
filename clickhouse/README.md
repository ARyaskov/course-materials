# Pulse — аналитическое хранилище событий на ClickHouse

Учебный сквозной проект курса «Эффективная работа с ClickHouse». `Pulse` хранит поток продуктовых событий и отвечает на аналитические вопросы: активность (DAU/WAU/MAU), удержание, воронки, ошибки по endpoint-ам, выручка.

Целевая версия: **ClickHouse 26.3**.

## Быстрый старт

```bash
# 1. Поднять локальный ClickHouse
docker compose up -d

# 2. Проверить, что сервер отвечает
docker exec -it pulse-clickhouse clickhouse-client \
  --user analyst --password analyst --database pulse --query "SELECT version()"

# 3. Применить схему хранения (актуальное определение таблиц)
docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ddl/retention.sql

# 4. Наполнить тестовыми данными
docker exec -i pulse-clickhouse clickhouse-client --user analyst --password analyst \
  --database pulse --queries-file /dev/stdin < ingestion/generate_events.sql

# 5. Остановить (данные в ./data сохранятся)
docker compose down
```

HTTP-интерфейс: `http://localhost:8123` (Play UI — `/play`), native-протокол: порт `9000`.
Учётные данные `analyst` / `analyst` — **только для локальной разработки**.

Стенд с брокером сообщений (глава 6): см. `ingestion/README.md`.

## Структура репозитория

```text
pulse/
  docker-compose.yml        # локальный стенд ClickHouse 26.3
  docker-compose.kafka.yml  # дополнение: Apache Kafka для потоковой загрузки
  config/users.d/           # дополнительные настройки пользователей
  ddl/                      # CREATE TABLE, materialized views, projections
  ingestion/                # загрузка событий: симулятор, файлы, запросы
  queries/                  # аналитические запросы дашборда
  data/                     # данные ClickHouse (в .gitignore)
```

## Актуальная схема

Определение `pulse.events` менялось по ходу курса; актуальная версия — в `ddl/retention.sql`:

- `raw_events (received_at, payload String)` — сырой слой, партиции по дню, TTL 3 дня;
- `events` — чистый слой: типизированные колонки, `PARTITION BY toYYYYMM(event_time)`, `ORDER BY (event_time, event_type, user_id)`, TTL 90 дней.

`ddl/events.sql` и `ddl/events_typed.sql` сохранены как этапы (главы 2 и 3) и на свежем стенде не нужны.

## Артефакты по главам

| Глава | Файлы |
| --- | --- |
| 2. Установка и первые запросы | `docker-compose.yml`, `ddl/events.sql`, `ingestion/generate_events.sql`, `queries/ch2_basics.sql` |
| 3. Типы данных | `ddl/events_typed.sql` |
| 4. MergeTree | `queries/ch4_orderby_experiment.sql` |
| 5. Partitioning и TTL | `ddl/retention.sql` |
| 6. Ingestion | `docker-compose.kafka.yml`, `ddl/ingestion.sql`, `ingestion/app/`, `ingestion/files/`, `ingestion/load_files.sql`, `ingestion/export_month.sql`, `ingestion/README.md` |
| 7. Запросы и функции | `ddl/derived_columns.sql` (endpoint_group), `queries/ch7_product_analytics.sql`, симулятор дополнен атрибутами `latency_ms` и `plan` |
| 8. JOIN, словари, денормализация | `ddl/user_profiles.sql`, `ingestion/generate_profiles.sql`, `ingestion/files/countries.csv`, `ddl/dictionaries.sql`, `ddl/denormalize.sql`, `queries/ch8_user_attributes.sql` |
| 9. Индексы и поиск | `ddl/skip_indexes.sql` (received_at + idx_session/idx_received/idx_attr_keys), `ddl/logs.sql` (app_logs с text index), `ingestion/generate_logs.sql`, `queries/ch9_search.sql` |
| 10. Materialized Views | `ddl/materialized_views.sql` (4 инкрементальных + 4 обновляемых витрины, staging, `v_hourly_activity`), `ingestion/backfill_views.sql`, `queries/ch10_dashboard.sql` |
| 11. Projections | `ddl/projections.sql` (p_by_user, p_by_endpoint + парные в events_staging), `queries/ch11_projections.sql` |
| 12. Диагностика | `config/config.d/logs.xml` (TTL журналов), `config/users.d/profiles.xml` (профиль дашборда с кэшем результатов), монтирование `config.d` в compose, `queries/ch12_diagnostics.sql` |
| 13. Кластер | `cluster/` (compose 2×2 + Keeper, конфигурации, README), `ddl/cluster/00_database.sql`, `ddl/cluster/01_tables.sql`, `queries/ch13_cluster.sql`, симулятор: `PULSE_INSERT_TABLE` |
| 14. Объектное хранилище и озеро | `docker-compose.s3.yml` (MinIO + бакеты), `config/config.d/storage.xml` (диск s3 + кэш + политика tiered), `ddl/storage_tiering.sql`, `ingestion/generate_old_events.sql`, `ddl/named_collections.sql`, `ddl/lake.sql` (таблица S3 с раскладкой Hive), `ingestion/export_lake.sql`, `queries/ch14_lake.sql` |

| 15. Наблюдаемость | `ddl/observability.sql` (logs_in → app_logs/app_logs_debug, logs_by_minute, metrics + metrics_1m, spans, ch_health, query_health_1m), `ingestion/generate_metrics.sql`, `ingestion/generate_spans.sql`, `config/config.d/prometheus.xml`, `config/otel-collector.yaml`, `queries/ch15_observability.sql` |

| 16. Векторы | `ddl/vectors.sql` (message_embeddings 128-d, message_embeddings_384, кластеры/центроиды, user_behavior_vectors 40-d + суточное обновляемое представление), `ingestion/build_embeddings.sql` (векторы в SQL без модели), `ingestion/embed_messages.py` (открытая модель, 384-d), `queries/ch16_vectors.sql` |

| 17. Доступ и безопасность | `ddl/access.sql` (роли, профили, гранты, политики строк, квоты, классы нагрузки, база audit, пользователи стенда), `config/config.d/security.xml` (TLS 8443/9440, маскирование, session_log), `scripts/gen_certs.sh`, `.env.example`, `queries/ch17_access_checks.sql`, `queries/ch17_audit.sql` |

| 18. Эксплуатация | `config/config.d/server.xml` (5 намеренных настроек), `scripts/backup.sh`, `scripts/restore_drill.sh`, `docs/runbooks.md` (куски, память, мутации, восстановление), `queries/ch18_incidents.sql`, `queries/ch18_mutations.sql` |

| 19. Архитектурные паттерны | `docs/architecture.md` (5 паттернов и решения), `ddl/orders_cdc.sql` (заказы как поток версий из PostgreSQL), `ddl/dashboard_live.sql` и `queries/ch19_dashboard_api.sql` (живой дашборд: витрина по минутам + хвост) |

| 20. Финальный проект | `docs/final_project.md` (задание, этапы → файлы, критерии, шкала), `scripts/apply_ddl.sh` (все DDL по порядку), `scripts/check.sh` + `queries/regression_checks.sql` |

## Одной командой

```bash
docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d && docker compose restart clickhouse
bash scripts/apply_ddl.sh          # вся схема, словари, витрины, проекции, индексы, доступ
python ingestion/app/emit_events.py --rate 500 --seconds 60
bash scripts/check.sh              # регрессии: индексы, проекции, сверки, словари, представления
```

## Эксплуатация

- **Копии:** `bash scripts/backup.sh full` (еженедельно) и `bash scripts/backup.sh` (ежедневно, инкрементальная) в бакет `pulse-backups`; ротация — 30 дней. Цель по потере данных — сутки; репетиция восстановления — `bash scripts/restore_drill.sh` ежемесячно, время записывается в `docs/runbooks.md`.
- **Руководства по инцидентам:** `docs/runbooks.md` — too many parts, memory limit exceeded, застрявшая мутация, восстановление таблицы.
- **Настройки:** изменение серверной настройки — правка `config/config.d/*.xml` с причиной в комментарии, `SYSTEM RELOAD CONFIG`, проверка `system.server_settings WHERE changed`, запись в журнал изменений. Не копировать наборы настроек из статей; не поднимать пороги кусков вместо исправления вставок.
- **Ежедневно:** `queries/ch12_diagnostics.sql` (снимок здоровья), `ch_health` вне нормы (`queries/ch15_observability.sql`, блок 5).

## Доступ

| Роль | Пользователь стенда | Права |
| --- | --- | --- |
| ingest | app_ingest | INSERT в точки входа (events_in, raw_events, logs_in, metrics, spans), dictGet словаря тарифов |
| analyst | alice | SELECT на витрины; на events — без user_id/session_id/attributes; свои строки query_log |
| analyst_eu | eve | как analyst, но политика строк: DE/FR/PL/GB; без витрин без страны |
| dashboard | dashboard | SELECT на витрины, профиль с кэшем и лимитами, квота |
| tenant_role | tenant_1, tenant_2 | events своего арендатора (политика по словарю user_tenants) |
| auditor | audit_reader | SELECT на базу audit |
| admin | — | всё |

Пароли в `ddl/access.sql` — заглушки для стенда; в продакшене — из секретов (`.env.example`). Перед продакшеном: закрыть незащищённые порты, заменить сертификат, включить `from_env` для ключей хранилища, ограничить `HOST` у пользователей.

## Векторы

Учебные векторы сообщений считаются в SQL по хешированным триграммам (128 измерений, лексическая близость) — работают без модели. Настоящие эмбеддинги (384 измерения, семантическая близость) — скрипт `ingestion/embed_messages.py` с открытой моделью, локально. Векторы поведения пользователей (40 признаков из событий за 30 дней) пересчитываются раз в сутки обновляемым представлением. Поиск — полный перебор с фильтрами; индекс векторного сходства оставлен закомментированным в `ddl/vectors.sql` для объёмов от миллионов строк (статус в сборке проверить).

## Наблюдаемость

Четыре таблицы телеметрии в одной базе, связанные идентификаторами: `app_logs` и `spans` — по `request_id`/`trace_id`, `metrics` — по меткам `endpoint`/`host`, `events` — по `user_id`/`session_id`. Здоровье сервера — `ch_health` (обновляемое представление раз в минуту из `system.*`), нагрузка запросов — `query_health_1m` (из `system.query_log` по метке `log_comment`). Порядок расследования: строка лога об ошибке → спаны того же `request_id` → событие продукта → запросы ClickHouse в ту же минуту (`queries/ch15_observability.sql`, блок 1). Метрики сервера для сборщиков — `http://localhost:9363/metrics` (порт пробрасывается при необходимости).

## Пирамида хранения

| Уровень | Где | Срок | Переход |
| --- | --- | --- | --- |
| сырьё `raw_events` | локальный диск | 3 дня | TTL DELETE |
| события `events`, горячие | локальный диск (том hot) | 30 дней | TTL `TO VOLUME 'cold'` |
| события `events`, холодные | MinIO `pulse-cold` через кэш | до 90 дней | TTL DELETE |
| озеро `lake_events` | MinIO `pulse-lake`, `events/month=YYYYMM/*.parquet` | бессрочно | `ingestion/export_lake.sql` в конце месяца |
| витрины | локальный диск | 2 года и дольше | TTL DELETE |

Стенд с MinIO: `docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d && docker compose restart clickhouse`. Внимание: MinIO занимает порт 9000 на хосте, native-порт ClickHouse при этом проброшен как 9010.

## Как расследовать медленный запрос

1. Найти в `system.query_log` формы запросов с наибольшей суммой времени (`queries/ch12_diagnostics.sql`, блок 10) и усилением чтения (блок 11).
2. Прочитать план: `EXPLAIN indexes = 1` — сколько гранул после ключа, есть ли `Skip` и проекция; `actions = 1` — что в PREWHERE; `PIPELINE` — одиночные процессоры.
3. Посмотреть, где время: `system.processors_profile_log` по `query_id` (нужен `SET log_processors_profiles = 1`).
4. Применить типовое исправление: условие на ключ вместо функции от него; существующая витрина/проекция/индекс; ограничение состояний или внешняя агрегация; маленькая сторона справа в JOIN или денормализованная колонка; `LIMIT` при сортировке.
5. Измерить снова по журналу (`read_rows`, `read_bytes`, `memory_usage`, `query_duration_ms`) и записать результат рядом с запросом.

## Какой вопрос каким механизмом обслуживается

| Вопрос | Механизм |
| --- | --- |
| агрегаты по времени (дашборд) | ключ сортировки + витрины (`ddl/materialized_views.sql`) |
| хронология пользователя, события endpoint-а | проекции `p_by_user`, `p_by_endpoint` |
| события сессии, свежие поступления, редкие атрибуты | индексы пропуска `idx_session`, `idx_received`, `idx_attr_keys` |
| поиск по словам в логах | текстовый индекс `app_logs.idx_message` |
| текущий тариф, регион, тариф на момент события | словари (`ddl/dictionaries.sql`) и колонка `plan` |

## Слой витрин

| Витрина | Отвечает на | Механизм | Отставание |
| --- | --- | --- | --- |
| `events_hourly` | события/ошибки/выручка по часам и типам | инкрементальная, SummingMergeTree | секунды |
| `events_errors` | ошибки endpoint-а за период | инкрементальная копия с ключом (endpoint_group, event_time) | секунды |
| `endpoint_hourly` | запросы, отказы, задержки по группам endpoint-ов | инкрементальная, SummingMergeTree | секунды |
| `events_hourly_users` | DAU/WAU/MAU, покупатели, перцентили по странам | инкрементальная, AggregatingMergeTree (состояния) | секунды |
| `retention_weekly`, `retention_summary` | удержание по когортам | обновляемые, раз в час | до часа |
| `plan_snapshot_daily` | распределение по тарифам по дням | обновляемая, APPEND, раз в день | до суток |
| `top_endpoints_daily` | топ-10 endpoint-ов за вчера | обновляемая поверх `endpoint_hourly` | до суток |

Чтение инкрементальных витрин всегда с повторной агрегацией (`sum`, `uniqCombinedMerge`, `quantilesTDigestMerge`). Пересборка месяца — `ingestion/backfill_views.sql`; запросы backfill обязаны совпадать с запросами представлений.

Артефакты следующих глав добавляются по мере прохождения курса.

## Порядок применения DDL на свежем стенде

```text
ddl/retention.sql          # raw_events, events
ddl/ingestion.sql          # конвейер загрузки, events_in, events_staging, ведомости
ddl/derived_columns.sql    # endpoint_group (events + events_staging)
ddl/user_profiles.sql      # профили и история тарифов
ingestion/generate_profiles.sql
ddl/dictionaries.sql       # countries, user_plan_current, user_plan_history_dict
ddl/denormalize.sql        # колонка plan — ЗАВИСИТ от словаря user_plan_current
ddl/skip_indexes.sql       # received_at + индексы пропуска events (+ events_staging)
ddl/logs.sql               # app_logs с текстовым индексом (может требовать SET allow_experimental_full_text_index)
ingestion/generate_logs.sql
ddl/materialized_views.sql # слой витрин (после derived_columns и user_profiles)
ddl/projections.sql        # проекции events (+ events_staging), материализация — мутации
```

Индексы `events` и запросы, ради которых они существуют, перечислены в шапке `ddl/skip_indexes.sql`; на данных симулятора индекс по `status` не даёт отсева и удаляется после практики главы 9.

Зависимость: после `ddl/denormalize.sql` вставки в `pulse.events` требуют существующего словаря `pulse.user_plan_current`. Любое изменение схемы `events` дублируется для `events_staging` (проверка — запрос `EXCEPT` по `system.columns` в конце `ddl/denormalize.sql`).
