# orders\_\_daily\_etl — финальный проект курса «Apache Airflow для Data Engineering»

Учебный, но production-like ETL-конвейер на **Apache Airflow 3**. Каждый день забирает
заказы, складывает сырой слой в объектное хранилище (MinIO), очищает данные и считает
витрину дневной выручки в PostgreSQL. Поддерживает повторные попытки, тайм-ауты, проверки
качества, уведомления о сбоях и backfill.

## Поток данных

```
HTTP API (или синтетика в учебном режиме)
    └─▶ raw      MinIO,       s3://raw/orders/<дата>.json
        └─▶ staging  PostgreSQL,  staging.orders          (типы, пустоты, дедуп, upsert)
            └─▶ витрина  PostgreSQL,  marts.daily_revenue (перезапись партиции за ds)
                └─▶ проверки качества (гейт перед витриной и после неё)
```

Граф DAG:

```
extract ─▶ load_staging ─▶ quality_gate_staging ─▶ build_mart ─▶ quality_gate_mart
```

## Требования

- Docker и Docker Compose;
- ~2 ГБ свободной оперативной памяти.

## Быстрый старт

```bash
# 1. Создать локальную конфигурацию (сам .env не хранится в Git).
cp .env.example .env
# Linux: заменить AIRFLOW_UID в .env на результат id -u,
# чтобы Airflow мог писать в ./logs. Windows/macOS: оставить 50000.

# 2. собрать образ и поднять инфраструктуру
docker compose build
docker compose up airflow-init     # один раз: миграция базы метаданных
docker compose up -d

# 3. проверить, что сервисы поднялись
docker compose ps
```

Откройте **http://localhost:8080**. В режиме простой аутентификации Airflow 3 создаёт
пользователя `admin`, а сгенерированный пароль печатает в логах api-server:

```bash
docker compose logs airflow-apiserver | grep -i password
```

Базы и бакеты создаются автоматически при первом старте:

- PostgreSQL поднимает базу `warehouse` со схемами `raw / staging / marts`
  (см. `postgres-init/01-init-warehouse.sql`);
- MinIO получает бакеты `raw` и `processed` (одноразовый сервис `createbuckets`).

DAG `orders__daily_etl` уже активен (не на паузе). Запустите его вручную кнопкой ▶ или
дождитесь планового прогона, затем посмотрите результат:

```bash
docker compose exec postgres psql -U airflow -d warehouse \
  -c "SELECT * FROM marts.daily_revenue ORDER BY d DESC LIMIT 10;"
```

## Источник данных

По умолчанию проект работает в **учебном режиме**: модуль `extract` генерирует
детерминированный синтетический набор заказов за дату, поэтому конвейер запускается без
внешнего API. Часть сумм специально приходит строкой с разделителями (`1 200,50`), а в
набор подмешан дубль — чтобы шагу `transform` было что приводить к типам и дедуплицировать.

Чтобы подключить **реальный API**, задайте его базовый адрес в `include/orders/config.py`
(`ORDERS_API_BASE_URL`). Тогда `extract` пойдёт в него постранично, с таймаутом
(см. `fetch_orders_from_api`).

## Backfill

Историю пересчитывают идемпотентно (перезапись партиций), с ограничением параллелизма.
В Airflow 3 backfill запускают из веб-интерфейса (форма Backfill) или из командной строки:

```bash
docker compose exec airflow-scheduler \
  airflow dags backfill orders__daily_etl \
  --start-date 2026-01-01 --end-date 2026-01-07
```

Точный набор флагов зависит от версии Airflow 3.x — см. `airflow dags backfill --help`.

## Тесты

```bash
docker compose exec airflow-scheduler pytest -q
```

- `tests/test_transform.py` — проверяет очистку (типы, пустоты, дедуп) без Airflow;
- `tests/test_dags.py` — что DAG импортируется без ошибок и имеет ожидаемую структуру.

## Структура проекта

```
airflow/
├── dags/
│   └── orders_daily_etl.py         # тонкий DAG: только проводка задач
├── include/
│   ├── orders/
│   │   ├── config.py               # id подключений, имя бакета, источник
│   │   ├── extract.py              # забор данных + сохранение raw
│   │   ├── transform.py            # типы, пустоты, дедупликация
│   │   ├── load.py                 # upsert в staging
│   │   ├── checks.py               # проверки качества
│   │   └── alerts.py               # уведомление о падении
│   └── sql/
│       ├── ddl.sql                 # схемы и таблицы warehouse (справка)
│       └── build_daily_revenue.sql # идемпотентная сборка витрины
├── postgres-init/                  # авто-создание базы warehouse и DDL
├── tests/
├── Dockerfile                      # образ Airflow + зависимости проекта
├── docker-compose.yaml
├── requirements.txt
└── .env.example                    # шаблон локального окружения
```

## Соответствие курсу

| Глава | Где в проекте |
|-------|----------------|
| 2. Локальная среда | `docker-compose.yaml`, `Dockerfile`, `.env.example`, `postgres-init/` |
| 3. Первый DAG | `dags/orders_daily_etl.py` |
| 4. Params / XCom / Connections | передача путей между задачами, `conn_id`, `template_searchpath` |
| 5. Внешние системы | `extract.py` (API, MinIO), `load.py` (PostgreSQL) |
| 6. ETL до витрины | `extract` → `transform` → `load` → `build_mart` |
| 7. Надёжность | `default_args`: `retries`, `retry_delay`, `execution_timeout` |
| 8. Backfill | идемпотентная перезапись партиций в `build_daily_revenue.sql` |
| 9. Качество и алерты | `checks.py`, `alerts.py`, `doc_md`, теги |
| 10. Финальный проект | весь проект целиком |

## Заметки

- Версия образа — `apache/airflow:3.0.3`; берите актуальную из ветки 3.x. Для
  воспроизводимой сборки зависимостей используйте constraints-файл Airflow.
- Это учебный стенд на одной машине (`LocalExecutor`). Масштабирование (Celery,
  Kubernetes), вынос преобразований в dbt или Spark и переезд в облачное хранилище
  подключаются без переписывания структуры — об этом урок 10.4.
- Остановить стенд: `docker compose down`. Полный сброс вместе с данными:
  `docker compose down -v` (стирает тома PostgreSQL и MinIO).
