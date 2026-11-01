"""Схемы регистрации и входа."""

from datetime import datetime

from pydantic import Field

from depot.api.v1.schemas.base import InputSchema, OutputSchema
from depot.api.v1.schemas.types import Email, Name, Password
from depot.domain.enums import UserRole


class RegisterRequest(InputSchema):
    email: Email
    password: Password
    full_name: Name


class LoginRequest(InputSchema):
    email: Email
    # ограничение сверху есть и здесь: без него длинная строка уходит
    # в функцию хеширования и превращает вход в дорогую операцию
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(InputSchema):
    refresh_token: str = Field(min_length=16, max_length=256)


class ChangePasswordRequest(InputSchema):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: Password


class TokenPairOut(OutputSchema):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int


class UserOut(OutputSchema):
    id: int
    email: str
    full_name: str
    role: UserRole
    station_id: int | None = None
    is_active: bool
    created_at: datetime


class ProfileOut(UserOut):
    """Собственный профиль.

    Список прав отдаётся вычисленным: клиент не должен воспроизводить
    таблицу ролей, чтобы решить, показывать ли кнопку.
    """

    permissions: list[str]
