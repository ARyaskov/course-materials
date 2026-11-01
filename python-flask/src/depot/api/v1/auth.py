"""Регистрация, вход, обновление и выход."""

from typing import Any

from flask import current_app, jsonify, request

from depot.api.auth import call_context, current_user
from depot.api.deps import auth_service
from depot.api.docs.registry import document
from depot.api.v1 import bp
from depot.api.v1.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    ProfileOut,
    RefreshRequest,
    RegisterRequest,
    TokenPairOut,
    UserOut,
)
from depot.domain.permissions import permissions_of
from depot.services.commands import RegisterUserCommand
from depot.services.tokens import TokenPairResult


def _token_response(pair: TokenPairResult) -> Any:
    """Сборка ответа с парой токенов.

    Срок жизни отдаётся числом секунд, а не меткой времени: клиенту не нужно
    сверять свои часы с серверными, чтобы понять, когда обновляться.
    """
    body = TokenPairOut(
        access_token=pair.access.value,
        refresh_token=pair.refresh.value,
        expires_in=int(current_app.config["ACCESS_TOKEN_TTL_SECONDS"]),
    )
    # пара токенов не кешируется ни при каких условиях
    return jsonify(body.public()), 200, {"Cache-Control": "no-store"}


@bp.post("/auth/register")
@document(summary="Регистрация", tags=["auth"], status=201, public=True)
def register() -> Any:
    payload = RegisterRequest.model_validate(request.get_json())
    user = auth_service().register(
        RegisterUserCommand(
            email=payload.email,
            password=payload.password,
            full_name=payload.full_name,
        )
    )
    return jsonify(UserOut.model_validate(user).public()), 201


@bp.post("/auth/login")
@document(summary="Вход", tags=["auth"], public=True)
def login() -> Any:
    """Вход по паролю.

    Ответ на неверный пароль и на несуществующий адрес одинаков —
    иначе форма входа превращается в способ проверить, зарегистрирован ли
    человек в сервисе.
    """
    payload = LoginRequest.model_validate(request.get_json())
    pair = auth_service().login(
        email=payload.email,
        password=payload.password,
        client_ip=request.remote_addr or "",
        user_agent=request.headers.get("User-Agent", "")[:255],
    )
    return _token_response(pair)


@bp.post("/auth/refresh")
@document(summary="Обновление пары токенов", tags=["auth"], public=True)
def refresh() -> Any:
    """Обновление с ротацией.

    Использованный токен обновления сразу отзывается. Повторное
    предъявление означает, что копия токена ходит по рукам: тогда
    отзывается вся цепочка сессий пользователя.
    """
    payload = RefreshRequest.model_validate(request.get_json())
    pair = auth_service().refresh(
        payload.refresh_token,
        client_ip=request.remote_addr or "",
        user_agent=request.headers.get("User-Agent", "")[:255],
    )
    return _token_response(pair)


@bp.post("/auth/logout")
@document(summary="Выход", tags=["auth"], status=204)
def logout() -> Any:
    payload = RefreshRequest.model_validate(request.get_json())
    auth_service().logout(payload.refresh_token, ctx=call_context())
    # тело у 204 отсутствует по определению: возвращать сюда JSON
    # означает нарушить контракт статуса
    return "", 204


@bp.get("/auth/me")
@document(summary="Собственный профиль", tags=["auth"])
def me() -> Any:
    user = current_user()
    body = ProfileOut(
        **UserOut.model_validate(user).model_dump(),
        # список прав отдаётся вычисленным: клиенту не нужно воспроизводить
        # таблицу ролей, чтобы решить, показывать ли кнопку
        permissions=permissions_of(user.role),
    )
    return jsonify(body.public())


@bp.post("/auth/password")
@document(summary="Смена пароля", tags=["auth"], status=204)
def change_password() -> Any:
    """Смена пароля отзывает остальные сессии.

    Пароль меняют в том числе потому, что он скомпрометирован; оставить
    после этого живые токены обновления значит не решить задачу.
    """
    payload = ChangePasswordRequest.model_validate(request.get_json())
    auth_service().change_password(
        current_password=payload.current_password,
        new_password=payload.new_password,
        ctx=call_context(),
    )
    return "", 204
