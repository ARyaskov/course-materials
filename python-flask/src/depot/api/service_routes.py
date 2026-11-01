"""Служебные маршруты.

Живучесть и готовность разделены намеренно. Живучесть отвечает на вопрос
«процесс жив»; провал приводит к перезапуску контейнера. Готовность отвечает
на вопрос «можно ли слать трафик»; провал лишь выводит экземпляр из
балансировки. Если проверять базу в живучести, недоступность базы перезапустит
все реплики разом и добавит к отказу базы отказ приложения.
"""

import time
from typing import Any

from flask import Flask, current_app, jsonify
from sqlalchemy import text

from depot import API_VERSION, BUILD_COMMIT, BUILD_TIME, BUILD_VERSION
from depot.extensions import db

#: проверка готовности должна отвечать быстрее, чем истечёт таймаут
#: балансировщика, иначе она сама станет причиной вывода из ротации
READINESS_TIMEOUT_MS = 800


def _check_database() -> tuple[bool, float]:
    started = time.perf_counter()
    try:
        db.session.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 — причина уходит в журнал, наружу только флаг
        current_app.logger.warning("readiness: database check failed", exc_info=True)
        return False, (time.perf_counter() - started) * 1000
    return True, (time.perf_counter() - started) * 1000


def _check_cache() -> tuple[bool, float]:
    started = time.perf_counter()
    cache = current_app.extensions.get("cache")
    if cache is None:
        return True, 0.0
    try:
        cache.get("__readiness__")
    except Exception:  # noqa: BLE001
        current_app.logger.warning("readiness: cache check failed", exc_info=True)
        return False, (time.perf_counter() - started) * 1000
    return True, (time.perf_counter() - started) * 1000


def register_service_routes(app: Flask) -> None:
    @app.get("/healthz")
    def liveness() -> Any:
        # ни базы, ни кеша, ни очереди: только факт, что процесс отвечает
        return jsonify(status="ok"), 200

    @app.get("/readyz")
    def readiness() -> Any:
        state = current_app.extensions.get("shutdown_state", {"accepting": True})
        if not state["accepting"]:
            # выкладка идёт: новые запросы сюда слать не нужно
            return jsonify(status="draining"), 503

        db_ok, db_ms = _check_database()
        cache_ok, cache_ms = _check_cache()

        checks = {
            "database": {"ok": db_ok, "ms": round(db_ms, 1)},
            # кеш не критичен: сервис работает и без него, но факт полезен
            "cache": {"ok": cache_ok, "ms": round(cache_ms, 1)},
        }
        ready = db_ok
        return jsonify(status="ok" if ready else "degraded", checks=checks), (
            200 if ready else 503
        )

    @app.get("/version")
    def version() -> Any:
        return jsonify(
            version=BUILD_VERSION,
            commit=BUILD_COMMIT,
            built_at=BUILD_TIME,
            api=API_VERSION,
        )
