"""Load: идемпотентно положить очищенные заказы в staging PostgreSQL.

Запись через upsert по бизнес-ключу order_id: повторный запуск за ту же дату
обновляет строки, а не плодит дубли.
"""

from __future__ import annotations

import logging

import pandas as pd
from airflow.providers.postgres.hooks.postgres import PostgresHook

from include.orders import config

log = logging.getLogger(__name__)

UPSERT_SQL = """
INSERT INTO staging.orders (order_id, amount, currency, created_at, d)
VALUES (%(order_id)s, %(amount)s, %(currency)s, %(created_at)s, %(d)s)
ON CONFLICT (order_id) DO UPDATE
SET amount     = EXCLUDED.amount,
    currency   = EXCLUDED.currency,
    created_at = EXCLUDED.created_at,
    d          = EXCLUDED.d
"""


def upsert_staging(df: pd.DataFrame, date: str) -> int:
    """Идемпотентно записать заказы в staging.orders за дату. Вернуть число строк."""
    rows = [
        {
            "order_id": r.order_id,
            "amount": float(r.amount),
            "currency": r.currency,
            "created_at": r.created_at.to_pydatetime(),
            "d": date,  # партиция по дате запуска (ds)
        }
        for r in df.itertuples(index=False)
    ]
    if not rows:
        log.warning("upsert_staging: за %s нет строк для загрузки", date)
        return 0

    hook = PostgresHook(postgres_conn_id=config.WAREHOUSE_CONN_ID)
    conn = hook.get_conn()
    with conn:  # одна транзакция
        with conn.cursor() as cur:
            cur.executemany(UPSERT_SQL, rows)
    log.info("upsert_staging: %d строк в staging.orders за %s", len(rows), date)
    return len(rows)
