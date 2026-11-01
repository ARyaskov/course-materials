"""Финальный проект курса «Apache Airflow для Data Engineering».

Ежедневный ETL заказов:

    HTTP API (или синтетика) -> raw (MinIO) -> staging (PostgreSQL)
        -> витрина marts.daily_revenue (PostgreSQL) -> проверки качества

DAG намеренно тонкий: вся бизнес-логика живёт в пакете ``include.orders`` и
тестируется без Airflow. Здесь — только проводка задач, расписание и общие
гарантии надёжности (retries, тайм-аут, уведомление о падении).
"""

from __future__ import annotations

import json
import logging
from datetime import timedelta

import pendulum

from airflow.sdk import dag, task
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

from include.orders import config
from include.orders.extract import fetch_orders, save_raw
from include.orders.transform import normalize
from include.orders.load import upsert_staging
from include.orders.checks import assert_staging_ok, assert_mart_ok
from include.orders.alerts import alert_on_failure

log = logging.getLogger(__name__)

# Общие настройки задач: применяются ко всем шагам конвейера.
DEFAULT_ARGS = {
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=30),
    "on_failure_callback": alert_on_failure,
}

DOC_MD = """
### orders__daily_etl

Ежедневный ETL заказов: забор данных, очистка, дневная выручка.

**Входы:** Connection `minio` (сырой слой), Connection `warehouse` (staging и marts).

**Выходы:** `staging.orders`, `marts.daily_revenue` (партиция за `ds`).
"""


@dag(
    dag_id="orders__daily_etl",
    schedule="@daily",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    max_active_runs=3,
    tags=["orders", "etl", "course"],
    description="Ежедневный ETL заказов: API -> raw -> staging -> витрина выручки",
    doc_md=DOC_MD,
    default_args=DEFAULT_ARGS,
    template_searchpath="/opt/airflow",  # чтобы найти include/sql/*.sql
)
def orders_daily_etl():

    @task
    def extract(date: str) -> str:
        """Забрать заказы за дату и сохранить сырой ответ в объектное хранилище."""
        records = fetch_orders(date)
        path = save_raw(records, date)
        log.info("extract: %d записей за %s -> %s", len(records), date, path)
        return path

    @task
    def load_staging(raw_path: str, date: str) -> int:
        """Прочитать raw, очистить и идемпотентно загрузить в staging."""
        from airflow.io.path import ObjectStoragePath

        raw = ObjectStoragePath(raw_path, conn_id=config.OBJECT_STORE_CONN_ID)
        records = json.loads(raw.read_bytes().decode("utf-8"))
        df = normalize(records)
        return upsert_staging(df, date)

    @task
    def quality_gate_staging(date: str) -> int:
        """Жёсткий quality gate перед сборкой витрины."""
        return assert_staging_ok(date)

    build_mart = SQLExecuteQueryOperator(
        task_id="build_mart",
        conn_id=config.WAREHOUSE_CONN_ID,
        sql="include/sql/build_daily_revenue.sql",
        params={"run_date": "{{ ds }}"},
    )

    @task
    def quality_gate_mart(date: str) -> int:
        """Проверка витрины после сборки."""
        return assert_mart_ok(date)

    ds = "{{ ds }}"
    raw_path = extract(ds)
    staged = load_staging(raw_path, ds)
    gate_staging = quality_gate_staging(ds)
    mart_check = quality_gate_mart(ds)

    # extract -> load_staging -> gate -> build_mart -> mart_check
    staged >> gate_staging >> build_mart >> mart_check


orders_daily_etl()
