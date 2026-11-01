"""Фабрика приложения.

Ничего не происходит до вызова функции: тест создаёт своё приложение
с тестовой конфигурацией, воркер — своё, сервер приложений — своё.
Состояние не разделяется, импорт остаётся дешёвым.

Порядок шагов обоснован: конфигурация первой, проверка сразу за ней,
расширения до blueprint, обработчики ошибок после маршрутов.
"""

import logging
import os
import signal
from typing import Any

from flask import Flask

from depot.config import get_config, mask_dsn, validate_config

__all__ = ["create_app", "BUILD_VERSION", "BUILD_COMMIT", "BUILD_TIME", "API_VERSION"]

#: значения приходят из сборки образа: вычислять их в контейнере нельзя —
#: репозитория там нет
BUILD_VERSION = os.environ.get("DEPOT_BUILD_VERSION", "dev")
BUILD_COMMIT = os.environ.get("DEPOT_BUILD_COMMIT", "unknown")
BUILD_TIME = os.environ.get("DEPOT_BUILD_TIME", "unknown")
API_VERSION = "1.0.0"


def create_app(config_name: str | None = None, **overrides: Any) -> Flask:
    app = Flask(__name__)
    app.config.from_object(get_config(config_name))
    # переопределения нужны тестам: изменить одну настройку без нового класса
    app.config.update(overrides)
    validate_config(app)

    _configure_logging(app)
    _configure_json(app)
    _register_extensions(app)
    _register_components(app)
    _register_hooks(app)
    _register_blueprints(app)
    _register_service_routes(app)
    _register_error_handlers(app)
    _register_docs(app)
    _register_cli(app)
    _register_shutdown(app)

    app.logger.info(
        "starting %s",
        BUILD_VERSION,
        extra={
            "commit": BUILD_COMMIT,
            "env": app.config["ENV_NAME"],
            "database": mask_dsn(app.config["SQLALCHEMY_DATABASE_URI"]),
            "docs_enabled": app.config["DOCS_ENABLED"],
        },
    )
    return app


def _configure_logging(app: Flask) -> None:
    from depot.observability.logs import configure_logging

    configure_logging(app.config["LOG_LEVEL"], app.config["LOG_FORMAT"])


def _configure_json(app: Flask) -> None:
    from depot.api.serialization import DepotJSONProvider

    app.json = DepotJSONProvider(app)


def _register_extensions(app: Flask) -> None:
    # локальные импорты разрывают цикл «приложение → blueprint → расширения»
    # по построению и оставляют `import depot` дешёвым
    from depot.extensions import db, migrate

    db.init_app(app)
    migrate.init_app(app, db)

    # модели импортируются, чтобы метаданные наполнились до генерации миграций
    import depot.domain.models  # noqa: F401


def _register_components(app: Flask) -> None:
    from depot.container import build_components

    app.extensions.update(build_components(app.config))


def _register_hooks(app: Flask) -> None:
    from depot.api.hooks import register_hooks

    register_hooks(app)


def _register_blueprints(app: Flask) -> None:
    from depot.api.v1 import bp as v1_bp

    app.register_blueprint(v1_bp, url_prefix="/api/v1")


def _register_service_routes(app: Flask) -> None:
    from depot.api.service_routes import register_service_routes

    register_service_routes(app)


def _register_error_handlers(app: Flask) -> None:
    from depot.api.errors import register_error_handlers

    register_error_handlers(app)


def _register_docs(app: Flask) -> None:
    from depot.api.docs.builder import build_openapi

    # документ собирается всегда: он нужен тестам и экспорту
    app.extensions["openapi"] = build_openapi(app)

    if not app.config["DOCS_ENABLED"]:
        return

    from depot.api.docs.views import bp as docs_bp

    app.register_blueprint(docs_bp, url_prefix="/api/v1")


def _register_cli(app: Flask) -> None:
    from depot.cli import register_cli

    register_cli(app)


def _register_shutdown(app: Flask) -> None:
    """Отказ готовности по сигналу завершения.

    Балансировщик перестаёт слать новые запросы, а текущие дорабатываются.
    Без этого выкладка обрывает запросы, которые были в обработке.
    """
    state = {"accepting": True}
    app.extensions["shutdown_state"] = state

    def handle_term(signum: int, frame: Any) -> None:
        state["accepting"] = False
        logging.getLogger("depot").info("shutdown signal received")

    try:
        signal.signal(signal.SIGTERM, handle_term)
    except ValueError:
        # не главный поток (например, в тестах) — сигнал не установить
        pass
