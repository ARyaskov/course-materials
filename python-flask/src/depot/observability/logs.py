"""Журналирование.

Приложение пишет в стандартный поток: файлами занимается среда исполнения.
В многопроцессной конфигурации несколько воркеров, пишущих в один файл,
перезаписывают записи друг друга при повороте.
"""

import json
import logging
import logging.config
from collections.abc import Mapping
from typing import Any

from flask import g, has_app_context, has_request_context

#: поля, значения которых заменяются на маркер перед записью
SENSITIVE_KEYS = frozenset(
    {
        "password",
        "new_password",
        "current_password",
        "token",
        "access_token",
        "refresh_token",
        "authorization",
        "secret",
        "api_key",
        "card_number",
    }
)

_RESERVED = frozenset(
    logging.LogRecord("", 0, "", 0, "", None, None).__dict__
) | {"message", "asctime", "taskName"}


def redact(data: Mapping[str, Any]) -> dict[str, Any]:
    """Вычистить чувствительные поля.

    Функция одна на проект и применяется везде, где структура попадает в журнал.
    """
    return {
        key: ("***" if key.lower() in SENSITIVE_KEYS else value)
        for key, value in data.items()
    }


class RequestContextFilter(logging.Filter):
    """Подставляет идентификатор запроса и пользователя автоматически.

    Передавать их в каждый вызов утомительно и легко забыть.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        request_id = ""
        user_id = None
        role = None

        if has_app_context() or has_request_context():
            request_id = g.get("request_id", "") if g else ""
            actor = g.get("actor") if g else None
            if actor is not None:
                user_id = actor.id
                role = str(actor.role)

        if not hasattr(record, "request_id"):
            record.request_id = request_id
        if not hasattr(record, "user_id"):
            record.user_id = user_id
        if not hasattr(record, "role"):
            record.role = role
        return True


class JsonFormatter(logging.Formatter):
    """Структурный формат: система сбора индексирует поля.

    Строка вида «POST /bookings 409» читается человеком и требует разбора
    регулярным выражением, чтобы найти все записи по одной брони.
    """

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in _RESERVED and not key.startswith("_"):
                payload[key] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # ensure_ascii=False оставляет русский текст читаемым;
        # default=str страхует от объектов, не сериализуемых в JSON
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging(level: str = "INFO", fmt: str = "plain") -> None:
    logging.config.dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "filters": {
                "request_context": {"()": RequestContextFilter},
            },
            "formatters": {
                "json": {"()": JsonFormatter},
                "plain": {
                    "format": "%(asctime)s %(levelname)-7s %(name)s %(message)s"
                },
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                    "formatter": "json" if fmt == "json" else "plain",
                    "filters": ["request_context"],
                },
            },
            "root": {"level": level, "handlers": ["console"]},
            "loggers": {
                "depot": {"level": level},
                # без этого SQLAlchemy на INFO зальёт журнал текстами запросов
                "sqlalchemy.engine": {"level": "WARNING"},
                "werkzeug": {"level": "WARNING"},
                "httpx": {"level": "WARNING"},
                "botocore": {"level": "WARNING"},
            },
        }
    )
