"""Контекст приложения для фоновых задач.

Воркер — отдельный процесс: контекста запроса в нём нет, `current_app`
не установлен, сессия базы не открыта. Приложение создаётся один раз
на процесс и переиспользуется всеми задачами: создавать его на каждую
задачу означает открывать новый пул соединений сотни раз в минуту.
"""

import logging
import os
from collections.abc import Callable
from functools import wraps
from typing import Any, TypeVar
from uuid import uuid4

from flask import Flask, g

log = logging.getLogger(__name__)

F = TypeVar("F", bound=Callable[..., Any])

_app: Flask | None = None


def worker_app() -> Flask:
    """Приложение процесса-воркера.

    Ленивое создание, а не импорт на уровне модуля: иначе задача, которую
    просто импортировали для проверки типов, поднимет соединения к базе.
    """
    global _app
    if _app is None:
        from depot import create_app

        _app = create_app(os.environ.get("DEPOT_ENV"))
        log.info("worker application created", extra={"pid": os.getpid()})
    return _app


def job(func: F) -> F:
    """Обёртка задачи: контекст приложения и идентификатор выполнения.

    `__wrapped__`, который проставляет `wraps`, позволяет тесту вызвать
    исходную функцию внутри уже открытого контекста и не создавать второе
    приложение.
    """

    @wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        with worker_app().app_context():
            # у задачи тоже есть идентификатор: без него строки журнала
            # воркера невозможно связать между собой
            g.request_id = kwargs.pop("request_id", None) or uuid4().hex
            log.info("job started", extra={"job": func.__name__})
            try:
                result = func(*args, **kwargs)
            except Exception:
                # запись до повторного возбуждения: RQ сохранит трассировку
                # у себя, но в общий журнал она не попадёт
                log.exception("job failed", extra={"job": func.__name__})
                raise
            log.info("job finished", extra={"job": func.__name__})
            return result

    return wrapper  # type: ignore[return-value]


def component(name: str) -> Any:
    from flask import current_app

    return current_app.extensions[name]
