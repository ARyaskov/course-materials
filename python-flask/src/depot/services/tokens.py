"""Выпуск и проверка токенов.

Содержимое JWT не зашифровано, а закодировано: в токен не кладётся ничего,
что не должно быть видно клиенту. Список прав туда не идёт — он выводится
из роли, а токен передаётся в каждом запросе.
"""

import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import uuid4

import jwt

from depot.domain.enums import UserRole
from depot.domain.errors import InvalidToken, TokenExpired
from depot.domain.ids import UserId
from depot.services.protocols import Clock


@dataclass(frozen=True, slots=True)
class IssuedToken:
    value: str
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: UserId
    role: UserRole
    station_id: int | None
    password_changed_at: int
    token_id: str


@dataclass(frozen=True, slots=True)
class TokenPairResult:
    access: IssuedToken
    refresh: IssuedToken

    @property
    def expires_in(self) -> int:
        return int((self.access.expires_at - datetime.now(self.access.expires_at.tzinfo)).total_seconds())


class TokenService:
    def __init__(
        self,
        *,
        keys: dict[str, str],
        current_key_id: str,
        issuer: str,
        audience: str,
        access_ttl: timedelta,
        refresh_ttl: timedelta,
        clock: Clock,
    ) -> None:
        self._keys = keys
        self._current_key_id = current_key_id
        self._issuer = issuer
        self._audience = audience
        self._access_ttl = access_ttl
        self._refresh_ttl = refresh_ttl
        self._clock = clock

    def issue_access(self, user) -> IssuedToken:  # type: ignore[no-untyped-def]
        now = self._clock.now()
        expires_at = now + self._access_ttl
        payload = {
            "sub": str(user.id),
            "iss": self._issuer,
            "aud": self._audience,
            "iat": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "jti": uuid4().hex,
            "role": str(user.role),
            "station_id": user.station_id,
            # момент смены пароля: механизм массового отзыва
            "pwd_at": int(user.password_changed_at.timestamp()),
        }
        value = jwt.encode(
            payload,
            self._keys[self._current_key_id],
            algorithm="HS256",
            headers={"kid": self._current_key_id},
        )
        return IssuedToken(value=value, expires_at=expires_at)

    def issue_refresh(self, user) -> IssuedToken:  # type: ignore[no-untyped-def]
        """Токен обновления — случайная строка, а не подписанный токен.

        Он хранится в базе (в виде хеша) и потому отзывается мгновенно;
        подпись здесь не нужна.
        """
        now = self._clock.now()
        return IssuedToken(
            value=f"rt_{secrets.token_urlsafe(48)}",
            expires_at=now + self._refresh_ttl,
        )

    def decode_access(self, token: str) -> AccessClaims:
        # из непроверенного заголовка берётся только идентификатор ключа,
        # и он выбирается из закрытого набора — подставить произвольное
        # значение бесполезно
        try:
            header = jwt.get_unverified_header(token)
        except jwt.InvalidTokenError:
            raise InvalidToken("Токен недействителен") from None

        secret = self._keys.get(header.get("kid", ""))
        if secret is None:
            raise InvalidToken("Неизвестный ключ подписи")

        try:
            payload = jwt.decode(
                token,
                secret,
                # список алгоритмов задан явно: иначе подмена на «без подписи»
                # даёт полный обход аутентификации
                algorithms=["HS256"],
                issuer=self._issuer,
                audience=self._audience,
                options={"require": ["exp", "iat", "sub", "jti"]},
                # допуск на расхождение часов; больше — маскировка проблемы
                leeway=10,
            )
        except jwt.ExpiredSignatureError:
            raise TokenExpired("Срок действия токена истёк") from None
        except jwt.InvalidTokenError:
            raise InvalidToken("Токен недействителен") from None

        return AccessClaims(
            user_id=UserId(int(payload["sub"])),
            role=UserRole(payload["role"]),
            station_id=payload.get("station_id"),
            password_changed_at=int(payload.get("pwd_at", 0)),
            token_id=str(payload["jti"]),
        )
