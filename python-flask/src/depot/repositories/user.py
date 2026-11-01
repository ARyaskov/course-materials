"""Пользователи и проверка учётных данных."""

import hashlib
import hmac
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from werkzeug.security import check_password_hash, generate_password_hash

from depot.domain.errors import InvalidCredentials, NotFound
from depot.domain.ids import UserId
from depot.domain.models import User
from depot.repositories.errors import translate_integrity_error

#: хеш заведомо неверного пароля для выравнивания времени ответа
_DUMMY_HASH = generate_password_hash("dummy-password-for-timing-safety")


def _dummy_verify() -> None:
    """Проверка против фиктивного хеша.

    Без неё ответ для несуществующего адреса приходит заметно быстрее,
    и разница во времени позволяет выяснить, зарегистрирован ли адрес.
    """
    check_password_hash(_DUMMY_HASH, "whatever")


def needs_rehash(password_hash: str) -> bool:
    """Хеш создан со старыми параметрами и должен быть пересчитан."""
    return not password_hash.startswith("scrypt:32768:8:1$")


class UserRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def find(self, user_id: UserId) -> User | None:
        return self._session.get(User, user_id)

    def get(self, user_id: UserId) -> User:
        user = self.find(user_id)
        if user is None:
            raise NotFound(f"пользователь {user_id} не найден")
        return user

    def by_email(self, email: str) -> User | None:
        stmt = select(User).where(func.lower(User.email) == email.lower())
        return self._session.scalars(stmt).one_or_none()

    def authenticate(self, email: str, password: str) -> User:
        """Проверка учётных данных.

        Сообщение одно для всех случаев: разные тексты дают способ проверять
        существование учётных записей.
        """
        user = self.by_email(email)
        if user is None or not user.is_active:
            _dummy_verify()
            raise InvalidCredentials("Неверный логин или пароль")

        if not check_password_hash(user.password_hash, password):
            raise InvalidCredentials("Неверный логин или пароль")

        if needs_rehash(user.password_hash):
            user.password_hash = generate_password_hash(password)

        return user

    def add(self, user: User) -> None:
        self._session.add(user)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise translate_integrity_error(exc) from exc

    def change_password(self, user: User, new_password: str, now: datetime) -> None:
        """Смена пароля отзывает ранее выданные токены доступа.

        Механизм — поле `pwd_at` в токене, которое сравнивается с этим значением.
        """
        user.password_hash = generate_password_hash(new_password)
        user.password_changed_at = now

    def count_active_admins(self) -> int:
        from depot.domain.enums import UserRole

        stmt = select(func.count()).select_from(
            select(User.id)
            .where(User.role == UserRole.ADMIN, User.is_active.is_(True))
            .subquery()
        )
        return self._session.scalar(stmt) or 0


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def constant_time_equals(left: str, right: str) -> bool:
    """Сравнение с постоянным временем.

    Обычное сравнение строк завершается на первом различии и позволяет
    подобрать значение побайтово.
    """
    return hmac.compare_digest(left, right)
