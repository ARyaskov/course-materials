"""Регистрация, вход и жизненный цикл сессий.

Токен доступа короткоживущий и не проверяется по базе — за это платят
задержкой отзыва. Токен обновления, наоборот, хранится в базе в виде хеша
и отзывается мгновенно; ротация при каждом обновлении делает кражу
заметной.
"""

import logging
import secrets
from collections.abc import Callable
from datetime import timedelta

from depot.domain.enums import UserRole
from depot.domain.errors import (
    InvalidCredentials,
    InvalidToken,
    TooManyAttempts,
    Unauthenticated,
)
from depot.domain.models import User
from depot.repositories.user import sha256_hex
from depot.services.commands import CallContext, RegisterUserCommand
from depot.services.protocols import Cache, Clock, Notifier
from depot.services.tokens import TokenPairResult, TokenService
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

#: окно и порог для ограничения попыток входа; счётчик ведётся по адресу
#: почты, а не по IP: за одним адресом сети сидит целый офис
LOGIN_WINDOW = timedelta(minutes=15)
LOGIN_ATTEMPTS = 10

WELCOME_TASK = "depot.jobs.notifications.send_welcome"


class AuthService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        clock: Clock,
        tokens: TokenService,
        cache: Cache,
        notifier: Notifier,
    ) -> None:
        self._uow_factory = uow_factory
        self._clock = clock
        self._tokens = tokens
        self._cache = cache
        self._notifier = notifier

    def register(self, command: RegisterUserCommand, ctx: CallContext | None = None) -> User:
        """Регистрация клиента.

        Роль не принимается из запроса ни при каких условиях: иначе первый
        же посетитель заведёт себе администратора.
        """
        from werkzeug.security import generate_password_hash

        with self._uow_factory() as uow:
            user = User(
                email=command.email,
                password_hash=generate_password_hash(command.password),
                full_name=command.full_name,
                role=UserRole.CLIENT,
                password_changed_at=self._clock.now(),
            )
            # уникальность адреса обеспечивает ограничение базы: проверка
            # «нет ли такого» отдельным запросом проигрывает гонку
            uow.users.add(user)
            log.info("user registered", extra={"user_id": user.id})
            return user

    def login(
        self, email: str, password: str, client_ip: str = "", user_agent: str = ""
    ) -> TokenPairResult:
        self._check_attempts(email)

        with self._uow_factory() as uow:
            try:
                user = uow.users.authenticate(email, password)
            except InvalidCredentials:
                self._register_attempt(email)
                raise

            if not user.is_active:
                # сообщение отличается от «неверный пароль»: человек с
                # заблокированной учётной записью должен понимать причину
                raise Unauthenticated("Учётная запись отключена")

            access = self._tokens.issue_access(user)
            refresh = self._tokens.issue_refresh(user)
            uow.sessions.store(
                user_id=user.id,
                token_hash=sha256_hex(refresh.value),
                expires_at=refresh.expires_at,
                ip=client_ip,
                user_agent=user_agent,
            )

        self._cache.delete(self._attempts_key(email))
        return TokenPairResult(access=access, refresh=refresh)

    def refresh(
        self, refresh_token: str, client_ip: str = "", user_agent: str = ""
    ) -> TokenPairResult:
        """Обновление с ротацией.

        Предъявленный токен отзывается сразу. Повторное предъявление
        отозванного означает, что копия ходит по рукам, — тогда
        отзывается вся цепочка сессий пользователя.
        """
        token_hash = sha256_hex(refresh_token)
        now = self._clock.now()

        with self._uow_factory() as uow:
            record = uow.sessions.find_active(token_hash, now)
            if record is None:
                stale = uow.sessions.find_by_hash(token_hash)
                if stale is not None:
                    log.warning(
                        "refresh token reuse detected",
                        extra={"user_id": stale.user_id},
                    )
                    uow.sessions.revoke_all_for_user(stale.user_id, now)
                raise InvalidToken("Токен обновления недействителен")

            user = uow.users.get(record.user_id)
            if not user.is_active:
                raise Unauthenticated("Учётная запись отключена")

            uow.sessions.revoke(record, now)
            access = self._tokens.issue_access(user)
            new_refresh = self._tokens.issue_refresh(user)
            uow.sessions.store(
                user_id=user.id,
                token_hash=sha256_hex(new_refresh.value),
                expires_at=new_refresh.expires_at,
                ip=client_ip,
                user_agent=user_agent,
            )

        return TokenPairResult(access=access, refresh=new_refresh)

    def logout(self, refresh_token: str, ctx: CallContext) -> None:
        """Выход из одной сессии.

        Отсутствие токена не считается ошибкой: повторное нажатие «выйти»
        не должно возвращать 404.
        """
        with self._uow_factory() as uow:
            record = uow.sessions.find_by_hash(sha256_hex(refresh_token))
            if record is not None and record.user_id == ctx.actor.id:
                uow.sessions.revoke(record, self._clock.now())

    def change_password(
        self, current_password: str, new_password: str, ctx: CallContext
    ) -> None:
        """Смена пароля отзывает остальные сессии.

        Пароль меняют в том числе потому, что он скомпрометирован; оставить
        после этого живые токены обновления значит не решить задачу.
        """
        now = self._clock.now()
        with self._uow_factory() as uow:
            user = uow.users.get(ctx.actor.id)
            uow.users.authenticate(user.email, current_password)
            uow.users.change_password(user, new_password, now)
            revoked = uow.sessions.revoke_all_for_user(user.id, now)

        log.info(
            "password changed",
            extra={"user_id": ctx.actor.id, "sessions_revoked": revoked},
        )

    def _attempts_key(self, email: str) -> str:
        # в ключ идёт хеш, а не сам адрес: содержимое кеша попадает в дампы
        # и в вывод отладочных команд
        return f"login:attempts:{sha256_hex(email.lower())}"

    def _check_attempts(self, email: str) -> None:
        attempts = self._cache.get(self._attempts_key(email))
        if attempts is not None and int(attempts) >= LOGIN_ATTEMPTS:
            raise TooManyAttempts(
                "Слишком много попыток входа",
                retry_after_seconds=int(LOGIN_WINDOW.total_seconds()),
            )

    def _register_attempt(self, email: str) -> None:
        """Счётчик неудачных попыток.

        Инкремент атомарен: чтение и запись двумя вызовами теряют попытки
        при параллельном переборе — то есть ровно тогда, когда счётчик нужен.
        Срок жизни выставляется каждый раз, поэтому окно скользящее.

        Кеш здесь не критичен: при недоступности Redis вход продолжает
        работать, а ограничение временно снимается. Отказ в аутентификации
        всему сервису хуже.
        """
        key = self._attempts_key(email)
        self._cache.incr(key)
        self._cache.expire(key, int(LOGIN_WINDOW.total_seconds()))

    @staticmethod
    def generate_temporary_password() -> str:
        """Временный пароль для восстановления доступа администратором."""
        return secrets.token_urlsafe(12)
