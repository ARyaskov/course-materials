"""Обработчики ошибок.

Flask выбирает обработчик по иерархии классов от конкретного к базовому,
поэтому порядок регистрации значения не имеет. Один обработчик на базовый
класс покрывает все доменные исключения: добавление нового не требует правок
в слое HTTP.
"""

import logging
from collections.abc import Mapping, Sequence
from typing import Any

from flask import Flask, g, request
from pydantic import ValidationError as PydanticValidationError
from werkzeug.exceptions import HTTPException

from depot.domain.errors import (
    DomainError,
    InfrastructureError,
    TooManyAttempts,
    Unauthenticated,
    ValidationError,
)

log = logging.getLogger(__name__)

HTTP_ERROR_CODES: dict[int, str] = {
    400: "bad_request",
    401: "unauthenticated",
    403: "permission_denied",
    404: "not_found",
    405: "method_not_allowed",
    406: "not_acceptable",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "unprocessable_entity",
    429: "rate_limited",
}

#: коды библиотеки сводятся к словарю проекта; ветка по умолчанию обязательна —
#: набор кодов меняется между версиями
CODE_MAP: dict[str, str] = {
    "missing": "required",
    "string_too_short": "too_short",
    "string_too_long": "too_long",
    "greater_than": "out_of_range",
    "greater_than_equal": "out_of_range",
    "less_than": "out_of_range",
    "less_than_equal": "out_of_range",
    "extra_forbidden": "unknown_field",
    "enum": "invalid_choice",
    "too_long": "too_long",
    "too_short": "too_short",
}

MESSAGES: dict[str, str] = {
    "required": "Поле обязательно",
    "too_short": "Значение слишком короткое",
    "too_long": "Значение слишком длинное",
    "out_of_range": "Значение вне допустимого диапазона",
    "unknown_field": "Неизвестное поле",
    "invalid_choice": "Недопустимое значение",
    "invalid_value": "Некорректное значение",
}

MAX_DETAILS = 20


def error_body(
    code: str,
    message: str,
    details: Sequence[Mapping[str, Any]] | None = None,
) -> dict[str, dict[str, Any]]:
    """Единственная функция сборки тела ошибки.

    Не обращается к базе и не выполняет сложных преобразований: вызывается
    в том числе из обработчика последней инстанции, где состояние приложения
    может быть повреждено.
    """
    error: dict[str, Any] = {
        "code": code,
        "message": message,
        "request_id": g.get("request_id", "") if g else "",
    }
    if details:
        error["details"] = [dict(d) for d in details]
    return {"error": error}


def format_location(loc: tuple[Any, ...]) -> str:
    """Путь к полю: точка для вложенных, индекс в скобках для элементов."""
    parts: list[str] = []
    for item in loc:
        if isinstance(item, int):
            parts.append(f"[{item}]")
        else:
            parts.append(f".{item}" if parts else str(item))
    return "".join(parts)


def map_code(pydantic_type: str) -> str:
    return CODE_MAP.get(pydantic_type, "invalid_value")


def safe_value(value: object, limit: int = 64) -> str:
    """Обрезка значения из запроса перед попаданием в сообщение.

    Иначе ошибка становится каналом для отражения произвольного текста.
    """
    text = str(value)
    return text[:limit] + "…" if len(text) > limit else text


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(PydanticValidationError)
    def handle_schema_error(exc: PydanticValidationError):  # type: ignore[no-untyped-def]
        details = []
        for error in exc.errors():
            code = map_code(error["type"])
            details.append(
                {
                    "field": format_location(error["loc"]) or "_",
                    "code": code,
                    # поле input не отдаётся: оно может содержать пароль
                    "message": MESSAGES.get(code, str(error["msg"])),
                }
            )
        truncated = len(details) > MAX_DETAILS
        message = "Запрос содержит некорректные данные"
        if truncated:
            message = f"{message}: найдено проблем — {len(details)}"
        return error_body("validation_failed", message, details[:MAX_DETAILS]), 400

    @app.errorhandler(ValidationError)
    def handle_validation(exc: ValidationError):  # type: ignore[no-untyped-def]
        return (
            error_body("validation_failed", "Запрос содержит некорректные данные", exc.details),
            400,
        )

    @app.errorhandler(TooManyAttempts)
    def handle_rate_limited(exc: TooManyAttempts):  # type: ignore[no-untyped-def]
        body = error_body(exc.code, str(exc))
        return body, exc.status, {"Retry-After": str(exc.retry_after_seconds)}

    @app.errorhandler(Unauthenticated)
    def handle_unauthenticated(exc: Unauthenticated):  # type: ignore[no-untyped-def]
        log.info("auth failed: %s", exc.code, extra={"path": request.path})
        return (
            error_body(exc.code, str(exc)),
            exc.status,
            {"WWW-Authenticate": 'Bearer realm="depot"'},
        )

    @app.errorhandler(DomainError)
    def handle_domain(exc: DomainError):  # type: ignore[no-untyped-def]
        # доменная ошибка — нормальная работа сервиса: уровень INFO, без
        # трассировки. Иначе доля 5xx перестаёт отражать здоровье сервиса.
        log.info("domain error: %s", exc.code, extra={"code": exc.code})
        return error_body(exc.code, str(exc), exc.details), exc.status

    @app.errorhandler(InfrastructureError)
    def handle_infrastructure(exc: InfrastructureError):  # type: ignore[no-untyped-def]
        log.error("infrastructure error: %s", exc.code, exc_info=True,
                  extra={"code": exc.code})
        # клиенту — нейтральное сообщение, подробности остаются в журнале
        return error_body(exc.code, "Сервис временно недоступен"), exc.status

    @app.errorhandler(HTTPException)
    def handle_http(exc: HTTPException):  # type: ignore[no-untyped-def]
        status = exc.code or 500
        code = HTTP_ERROR_CODES.get(status, "http_error")
        # заголовки исключения передаются дальше: 405 несёт Allow,
        # 401 — WWW-Authenticate
        return error_body(code, exc.description or ""), status, dict(exc.get_headers())

    @app.errorhandler(Exception)
    def handle_unexpected(exc: Exception):  # type: ignore[no-untyped-def]
        """Обработчик последней инстанции.

        Не обращается к базе и не сериализует сложные объекты: он вызывается
        и тогда, когда сломано всё остальное.
        """
        log.exception(
            "unhandled exception",
            extra={"path": request.path, "method": request.method},
        )
        return error_body("internal_error", "Внутренняя ошибка сервиса"), 500
