"""Аутентификация на границе HTTP.

Актор собирается из данных токена и не требует обращения к базе: этого
достаточно для проверки роли и правил видимости.
"""

import hashlib
from collections.abc import Callable
from functools import wraps
from typing import Any, TypeVar, cast

from flask import Request, current_app, g, request

from depot.domain.access import Actor
from depot.domain.enums import Permission
from depot.domain.errors import Unauthenticated
from depot.domain.permissions import require_permission
from depot.services.commands import CallContext

F = TypeVar("F", bound=Callable[..., Any])


def extract_bearer_token(req: Request) -> str | None:
    """Извлечение токена из заголовка.

    `partition` вместо `split` — корректно при отсутствии пробела;
    сравнение схемы без учёта регистра — часть клиентов шлёт `bearer`.
    """
    raw = req.headers.get("Authorization", "")
    scheme, _, token = raw.partition(" ")
    if scheme.lower() != "bearer":
        return None
    token = token.strip()
    return token or None


def authenticate(req: Request) -> Actor:
    from depot.api.deps import token_service

    token = extract_bearer_token(req)
    if token is None:
        raise Unauthenticated("Требуется авторизация")

    claims = token_service().decode_access(token)
    return Actor(
        id=claims.user_id,
        role=claims.role,
        station_id=claims.station_id,
        token_id=claims.token_id,
    )


def current_user() -> Any:
    """Полный объект пользователя — по требованию, а не на каждом запросе.

    Ленивая загрузка с кешированием в пределах запроса: обращение к базе
    происходит только там, где функция действительно нужна.
    """
    user = g.get("_current_user")
    if user is None:
        from depot.api.deps import user_repository

        user = user_repository().get(g.actor.id)
        g._current_user = user
    return user


def requires(permission: Permission) -> Callable[[F], F]:
    """Проверка права на операцию.

    Проверка на отсутствие актора страхует от применения декоратора
    в blueprint без хука аутентификации.
    """

    def decorator(view: F) -> F:
        @wraps(view)  # без него все обработчики получат имя wrapper
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            actor = g.get("actor")
            if actor is None:
                raise Unauthenticated("Требуется авторизация")
            require_permission(actor, permission)
            return view(*args, **kwargs)

        return cast(F, wrapper)

    return decorator


def call_context() -> CallContext:
    """Обстоятельства вызова для сервисного слоя.

    Живёт в слое HTTP: сервис получает готовый объект и работает одинаково,
    вызван он из API, из очереди или из командной строки.
    """
    return CallContext(
        actor=g.actor,
        request_id=g.get("request_id", ""),
        source="api",
        idempotency_key=request.headers.get("Idempotency-Key"),
        client_ip=request.remote_addr or "",
        # обрезка по длине колонки: значение приходит от клиента
        user_agent=request.headers.get("User-Agent", "")[:255],
    )


def anonymous_context() -> CallContext:
    from depot.domain.enums import UserRole
    from depot.domain.ids import UserId

    return CallContext(
        actor=Actor(id=UserId(0), role=UserRole.CLIENT),
        request_id=g.get("request_id", ""),
        source="api",
        client_ip=request.remote_addr or "",
        user_agent=request.headers.get("User-Agent", "")[:255],
    )


def system_context(source: str) -> CallContext:
    """Актор для фоновых задач и команд.

    Поле source отличает системные вызовы от пользовательских в журналах:
    запись «бронь отменена» без источника не отвечает на вопрос, кто это сделал.
    """
    from uuid import uuid4

    from depot.domain.enums import UserRole
    from depot.domain.ids import UserId

    return CallContext(
        actor=Actor(id=UserId(0), role=UserRole.ADMIN),
        request_id=uuid4().hex,
        source=source,
    )


def request_fingerprint(body: bytes) -> str:
    """Отпечаток тела для ключа идемпотентности."""
    return hashlib.sha256(body).hexdigest()


def require_json() -> Any:
    """Проверка типа содержимого для изменяющих методов."""
    if request.method in {"POST", "PUT", "PATCH"} and not request.is_json:
        from depot.domain.errors import UnsupportedMediaType

        raise UnsupportedMediaType("Ожидается application/json")
    return None


def max_photos() -> int:
    return int(current_app.config["MAX_PHOTOS"])
