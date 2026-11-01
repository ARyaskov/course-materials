"""Сборка документа OpenAPI из таблицы маршрутов.

Источник — сам Flask: `app.url_map` знает все пути, методы и типы
параметров. Документ, собранный из кода, не может описать несуществующий
маршрут и не может пропустить существующий.
"""

from typing import Any

from flask import Flask

from depot import API_VERSION
from depot.api.docs.registry import REGISTRY

#: методы, которые Flask добавляет сам; в документе им не место
IMPLICIT_METHODS = frozenset({"HEAD", "OPTIONS"})

#: преобразователи правил маршрутов → типы OpenAPI
CONVERTER_TYPES: dict[str, dict[str, str]] = {
    "int": {"type": "integer"},
    "float": {"type": "number"},
    "uuid": {"type": "string", "format": "uuid"},
    "string": {"type": "string"},
    "path": {"type": "string"},
    "default": {"type": "string"},
}

ERROR_RESPONSES: dict[str, dict[str, Any]] = {
    "400": {"description": "Некорректный запрос"},
    "401": {"description": "Требуется авторизация"},
    "403": {"description": "Недостаточно прав"},
    "404": {"description": "Не найдено"},
    "409": {"description": "Конфликт состояния"},
    "422": {"description": "Правило предметной области нарушено"},
    "429": {"description": "Слишком много запросов"},
}


def _openapi_path(rule: str) -> str:
    """Перевод правила Flask в шаблон OpenAPI.

    Flask пишет <uuid:booking_id>, OpenAPI ждёт {booking_id}.
    """
    parts: list[str] = []
    for chunk in rule.split("/"):
        if chunk.startswith("<") and chunk.endswith(">"):
            inner = chunk[1:-1]
            name = inner.split(":")[-1]
            parts.append("{" + name + "}")
        else:
            parts.append(chunk)
    return "/".join(parts)


def _path_parameters(rule: Any) -> list[dict[str, Any]]:
    params: list[dict[str, Any]] = []
    for name, converter in rule._converters.items():
        key = type(converter).__name__.replace("Converter", "").lower()
        params.append(
            {
                "name": name,
                "in": "path",
                # параметр пути обязателен всегда: без него маршрут
                # просто не совпадёт
                "required": True,
                "schema": CONVERTER_TYPES.get(key, CONVERTER_TYPES["default"]),
            }
        )
    return params


def build_openapi(app: Flask) -> dict[str, Any]:
    paths: dict[str, dict[str, Any]] = {}

    for rule in app.url_map.iter_rules():
        endpoint_name = rule.endpoint.rsplit(".", 1)[-1]
        meta = REGISTRY.get(endpoint_name)
        if meta is None:
            # служебные маршруты и статика в публичный документ не идут
            continue

        path = _openapi_path(str(rule))
        entry = paths.setdefault(path, {})

        for method in sorted((rule.methods or set()) - IMPLICIT_METHODS):
            responses: dict[str, Any] = {
                str(meta.status): {"description": "Успех"},
                **ERROR_RESPONSES,
            }
            operation: dict[str, Any] = {
                # идентификатор операции — имя обработчика: генераторы клиентов
                # делают из него имя метода
                "operationId": endpoint_name,
                "summary": meta.summary,
                "tags": meta.tags or ["default"],
                "responses": responses,
                "parameters": _path_parameters(rule),
            }
            if meta.deprecated:
                operation["deprecated"] = True
            if not meta.public:
                operation["security"] = [{"bearerAuth": []}]
            entry[method.lower()] = operation

    return {
        "openapi": "3.1.0",
        "info": {
            "title": "Depot API",
            "version": API_VERSION,
            "description": "API сети пунктов проката профессионального оборудования.",
        },
        "servers": [{"url": "/api/v1"}],
        "components": {
            "securitySchemes": {
                "bearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "JWT",
                }
            }
        },
        "paths": paths,
    }
