"""Проверки качества данных.

Гейты падают (поднимают исключение) при нарушении и тем самым останавливают
конвейер, не давая сомнительным данным дойти до витрины и до аналитика.
"""

from __future__ import annotations

import logging

from airflow.providers.postgres.hooks.postgres import PostgresHook

from include.orders import config

log = logging.getLogger(__name__)


def assert_staging_ok(date: str) -> int:
    """Жёсткий quality gate по staging за дату.

    Считает все метрики одним запросом (тяжёлое — на стороне базы) и падает,
    если данные пусты, есть NULL в ключе, отрицательные суммы или дубли.
    """
    hook = PostgresHook(postgres_conn_id=config.WAREHOUSE_CONN_ID)
    rows, nulls, negatives, dups = hook.get_first(
        """
        SELECT count(*),
               count(*) FILTER (WHERE order_id IS NULL),
               count(*) FILTER (WHERE amount < 0),
               count(*) - count(DISTINCT order_id)
        FROM staging.orders
        WHERE d = %(d)s
        """,
        parameters={"d": date},
    )
    if rows == 0:
        raise ValueError(f"quality gate: staging за {date} пуст")
    if nulls:
        raise ValueError(f"quality gate: {nulls} строк без order_id за {date}")
    if negatives:
        raise ValueError(f"quality gate: {negatives} отрицательных сумм за {date}")
    if dups:
        raise ValueError(f"quality gate: {dups} дублей order_id за {date}")
    log.info("quality gate: staging за %s в порядке (%d строк)", date, rows)
    return rows


def assert_mart_ok(date: str) -> int:
    """Проверка витрины за дату: не пусто и выручка неотрицательна."""
    hook = PostgresHook(postgres_conn_id=config.WAREHOUSE_CONN_ID)
    row = hook.get_first(
        "SELECT orders, revenue FROM marts.daily_revenue WHERE d = %(d)s",
        parameters={"d": date},
    )
    if row is None:
        raise ValueError(f"quality gate: витрина за {date} пуста")
    orders, revenue = row
    if revenue is None or revenue < 0:
        raise ValueError(f"quality gate: некорректная выручка за {date}: {revenue}")
    log.info("quality gate: витрина за %s — %s заказов, выручка %s", date, orders, revenue)
    return orders
