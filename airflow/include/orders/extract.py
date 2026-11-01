"""Extract: забрать заказы за дату и сохранить сырой ответ в объектное хранилище.

В учебном режиме источник синтетический (детерминированный по дате), чтобы
проект запускался без внешнего API. Реальный путь — постраничный забор из
HTTP API с таймаутом — включается, когда задан ``config.ORDERS_API_BASE_URL``.
"""

from __future__ import annotations

import json
import logging
import random

from airflow.io.path import ObjectStoragePath

from include.orders import config

log = logging.getLogger(__name__)


def fetch_orders(date: str) -> list[dict]:
    """Вернуть список заказов за дату из настроенного источника."""
    if config.ORDERS_API_BASE_URL:
        return fetch_orders_from_api(date)
    return _synthetic_orders(date)


def fetch_orders_from_api(date: str) -> list[dict]:
    """Реальный источник: постраничный забор из HTTP API с таймаутом.

    Повторные попытки и тайм-аут задачи навешивает сам DAG (default_args),
    здесь — только корректный обход страниц и таймаут на каждый запрос.
    """
    import httpx

    items: list[dict] = []
    with httpx.Client(base_url=config.ORDERS_API_BASE_URL, timeout=10.0) as client:
        page = 1
        while page <= 1000:  # потолок против бесконечной пагинации
            resp = client.get("/orders", params={"date": date, "page": page})
            resp.raise_for_status()
            batch = resp.json().get("items", [])
            if not batch:
                break
            items.extend(batch)
            page += 1
    return items


def _synthetic_orders(date: str) -> list[dict]:
    """Детерминированный синтетический набор заказов за дату (учебный режим).

    Часть сумм специально приходит строкой с разделителями («1 200,50»), а в
    набор подмешан дубль — чтобы шагу transform было что чистить и дедуплицировать.
    """
    rng = random.Random(date)  # один и тот же date -> один и тот же результат
    count = rng.randint(80, 200)
    orders: list[dict] = []
    for i in range(count):
        hour = rng.randint(0, 23)
        minute = rng.randint(0, 59)
        amount = rng.choice([
            f"{rng.randint(100, 5000)}",
            f"{rng.randint(1, 9)} {rng.randint(100, 999)},{rng.randint(0, 99):02d}",
        ])
        orders.append({
            "order_id": f"{date}-{i:04d}",
            "amount": amount,
            "currency": "RUB",
            "created_at": f"{date}T{hour:02d}:{minute:02d}:00+03:00",
        })
    if orders:
        orders.append(dict(orders[0]))  # дубль для демонстрации дедупликации
    return orders


def save_raw(records: list[dict], date: str) -> str:
    """Сохранить сырой JSON в объектное хранилище по дате. Вернуть путь.

    Одна дата — один файл (перезапись), поэтому повторный запуск extract не
    плодит копии, а заменяет результат тем же содержимым.
    """
    base = ObjectStoragePath(config.RAW_BUCKET, conn_id=config.OBJECT_STORE_CONN_ID)
    final = base / "orders" / f"{date}.json"
    try:
        final.parent.mkdir(parents=True, exist_ok=True)
    except Exception:  # у объектных хранилищ нет каталогов — это нормально
        pass
    payload = json.dumps(records, ensure_ascii=False).encode("utf-8")
    final.write_bytes(payload)
    log.info("save_raw: %d записей -> %s", len(records), final)
    return str(final)
