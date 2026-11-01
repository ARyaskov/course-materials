"""Конфигурация по окружениям.

Обязательные настройки объявлены без умолчаний: отсутствие переменной роняет
импорт с внятным сообщением, а не всплывает на сотом запросе.
"""

import os
import re
from typing import Any

from flask import Flask


def _env(name: str) -> str:
    try:
        return os.environ[name]
    except KeyError:
        raise RuntimeError(f"не задана переменная окружения {name}") from None


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    return int(raw) if raw else default


def mask_dsn(dsn: str) -> str:
    """Убрать пароль из строки подключения перед записью в журнал."""
    return re.sub(r"://([^:/@]+):[^@]*@", r"://\1:***@", dsn)


class BaseConfig:
    ENV_NAME = "base"

    SECRET_KEY = _env("DEPOT_SECRET_KEY")
    SQLALCHEMY_DATABASE_URI = _env("DEPOT_DATABASE_URL")
    REDIS_URL = _env("DEPOT_REDIS_URL")

    SQLALCHEMY_ENGINE_OPTIONS: dict[str, Any] = {
        "pool_size": _env_int("DEPOT_DB_POOL_SIZE", 5),
        "max_overflow": _env_int("DEPOT_DB_MAX_OVERFLOW", 5),
        # без него запрос ждёт свободного соединения бесконечно, занимая воркер
        "pool_timeout": 10,
        # меньше таймаута базы и сетевого оборудования
        "pool_recycle": 1800,
        # снимает ошибки «сервер закрыл соединение» после простоя
        "pool_pre_ping": True,
        "connect_args": {
            "application_name": "depot-api",
            "connect_timeout": 5,
            "options": "-c statement_timeout=5000",
        },
    }

    # согласовано с client_max_body_size прокси
    MAX_CONTENT_LENGTH = 25 * 1024 * 1024
    MAX_FILE_SIZE = 5 * 1024 * 1024
    MAX_PHOTOS = 10

    JSON_SORT_KEYS = False
    PROPAGATE_EXCEPTIONS = False
    TRAP_HTTP_EXCEPTIONS = False

    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    PREFERRED_URL_SCHEME = "https"

    #: ключ подписи и его идентификатор. Прошлый ключ остаётся в наборе
    #: на время ротации: иначе смена ключа мгновенно разлогинивает всех,
    #: у кого токен доступа ещё жив
    SECRET_KEY_PREVIOUS = os.environ.get("DEPOT_SECRET_KEY_PREVIOUS", "")
    TOKEN_KEY_ID = os.environ.get("DEPOT_TOKEN_KEY_ID", "v1")
    TOKEN_KEY_ID_PREVIOUS = os.environ.get("DEPOT_TOKEN_KEY_ID_PREVIOUS", "v0")

    ACCESS_TOKEN_TTL_SECONDS = 900
    REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 3600
    TOKEN_ISSUER = "depot-api"
    TOKEN_AUDIENCE = "depot-clients"

    QUEUE_BACKEND = os.environ.get("DEPOT_QUEUE", "redis")
    CACHE_BACKEND = os.environ.get("DEPOT_CACHE", "redis")
    CACHE_ENABLED = _env_bool("DEPOT_CACHE_ENABLED", True)
    CACHE_DEFAULT_TTL = 300
    STORAGE_BACKEND = os.environ.get("DEPOT_STORAGE", "local")
    STORAGE_PATH = os.environ.get("DEPOT_STORAGE_PATH", "./var/uploads")
    NOTIFICATIONS_BACKEND = os.environ.get("DEPOT_NOTIFICATIONS", "log")
    PAYMENT_BACKEND = os.environ.get("DEPOT_PAYMENT", "fake")
    PAYMENT_GATEWAY_URL = os.environ.get("DEPOT_PAYMENT_URL", "https://payments.invalid")
    PAYMENT_API_KEY = os.environ.get("DEPOT_PAYMENT_KEY", "")

    DOCS_ENABLED = _env_bool("DEPOT_DOCS_ENABLED", True)
    DOCS_PUBLIC = _env_bool("DEPOT_DOCS_PUBLIC", False)

    LOG_LEVEL = os.environ.get("DEPOT_LOG_LEVEL", "INFO")
    LOG_FORMAT = os.environ.get("DEPOT_LOG_FORMAT", "plain")

    DEBUG = False
    TESTING = False
    SQLALCHEMY_ECHO = False


class DevelopmentConfig(BaseConfig):
    ENV_NAME = "development"
    DEBUG = True
    SQLALCHEMY_ECHO = _env_bool("DEPOT_SQL_ECHO")


class TestingConfig(BaseConfig):
    ENV_NAME = "testing"
    TESTING = True
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DEPOT_TEST_DATABASE_URL",
        "postgresql+psycopg://depot:depot@localhost:5433/depot_test",
    )
    # тестовые реализации выбираются конфигурацией, а не патчем в тестах
    QUEUE_BACKEND = "memory"
    CACHE_BACKEND = "memory"
    STORAGE_BACKEND = "memory"
    NOTIFICATIONS_BACKEND = "memory"
    PAYMENT_BACKEND = "fake"
    DOCS_ENABLED = True


class ProductionConfig(BaseConfig):
    ENV_NAME = "production"
    LOG_FORMAT = "json"
    DOCS_ENABLED = _env_bool("DEPOT_DOCS_ENABLED", False)


_CONFIGS: dict[str, type[BaseConfig]] = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}


def get_config(name: str | None = None) -> type[BaseConfig]:
    resolved = name or os.environ.get("DEPOT_ENV", "development")
    try:
        return _CONFIGS[resolved]
    except KeyError:
        raise RuntimeError(
            f"неизвестное окружение {resolved!r}; допустимо: {', '.join(_CONFIGS)}"
        ) from None


REQUIRED_SETTINGS = ("SECRET_KEY", "SQLALCHEMY_DATABASE_URI", "REDIS_URL")
INSECURE_DEFAULTS = frozenset({"dev-only", "changeme", "secret", "test", ""})


def validate_config(app: Flask) -> None:
    """Проверки при старте.

    Каждая появилась после инцидента: приложение должно падать при неверной
    конфигурации, а не работать неправильно.
    """
    missing = [name for name in REQUIRED_SETTINGS if not app.config.get(name)]
    if missing:
        raise RuntimeError(f"не заданы настройки: {', '.join(missing)}")

    if app.config["DEBUG"] or app.config["TESTING"]:
        return

    if app.config["SECRET_KEY"] in INSECURE_DEFAULTS:
        raise RuntimeError("производственный запуск с отладочным SECRET_KEY")
    if len(app.config["SECRET_KEY"]) < 32:
        raise RuntimeError("SECRET_KEY короче 32 символов")
    if app.config["SQLALCHEMY_DATABASE_URI"].startswith("sqlite"):
        raise RuntimeError("производственный запуск с SQLite")
    if app.config["SQLALCHEMY_ECHO"]:
        raise RuntimeError("вывод SQL включён в production")
    if app.config["DOCS_ENABLED"] and not app.config["DOCS_PUBLIC"]:
        raise RuntimeError("документация включена без явного разрешения")
