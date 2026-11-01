"""Иерархия исключений приложения.

Разделение на доменные и инфраструктурные отвечает на три вопроса: виноват ли
клиент, нужно ли будить дежурного и имеет ли смысл повторить.
Код и статус живут в классе, поэтому слой HTTP обрабатывает их одним обработчиком.
"""

from collections.abc import Sequence
from datetime import datetime
from typing import Any


class DepotError(Exception):
    """Базовое исключение приложения."""

    code = "internal_error"
    status = 500

    @property
    def details(self) -> Sequence[dict[str, Any]]:
        return ()


class DomainError(DepotError):
    """Правило предметной области не позволяет выполнить операцию."""

    code = "domain_error"
    status = 422


class InfrastructureError(DepotError):
    """Внешняя система или ресурс недоступны."""

    code = "internal_error"
    status = 500


class TransientError(InfrastructureError):
    """Сбой, который может пройти сам: повтор имеет смысл."""

    status = 503


# --- ошибки границы системы -------------------------------------------------


class ValidationError(DomainError):
    code = "validation_failed"
    status = 400

    def __init__(self, message: str, *, field: str = "_", error_code: str = "invalid_value") -> None:
        super().__init__(message)
        self.field = field
        self.error_code = error_code

    @property
    def details(self) -> Sequence[dict[str, Any]]:
        return ({"field": self.field, "code": self.error_code, "message": str(self)},)


class UnsupportedMediaType(DomainError):
    code = "unsupported_media_type"
    status = 415


class PayloadTooLarge(DomainError):
    code = "payload_too_large"
    status = 413


# --- аутентификация и права -------------------------------------------------


class Unauthenticated(DomainError):
    code = "unauthenticated"
    status = 401


class TokenExpired(Unauthenticated):
    code = "token_expired"


class InvalidToken(Unauthenticated):
    code = "invalid_token"


class InvalidCredentials(Unauthenticated):
    code = "invalid_credentials"


class PermissionDenied(DomainError):
    code = "permission_denied"
    status = 403


class TooManyAttempts(DomainError):
    code = "rate_limited"
    status = 429

    def __init__(self, message: str, *, retry_after_seconds: int = 60) -> None:
        super().__init__(message)
        self.retry_after_seconds = retry_after_seconds


# --- правила домена ---------------------------------------------------------


class NotFound(DomainError):
    code = "not_found"
    status = 404


class InvalidTransition(DomainError):
    code = "invalid_transition"
    status = 409


class InvalidPeriod(DomainError):
    code = "invalid_period"
    status = 422


class BookingOverlap(DomainError):
    code = "booking_overlap"
    status = 409
    field = "starts_at"

    def __init__(
        self,
        message: str = "Выбранный интервал уже занят",
        *,
        busy_until: datetime | None = None,
    ) -> None:
        super().__init__(message)
        self.busy_until = busy_until

    @property
    def details(self) -> Sequence[dict[str, Any]]:
        if self.busy_until is None:
            return ()
        return (
            {
                "field": self.field,
                "code": self.code,
                "message": f"Интервал занят до {self.busy_until:%d.%m.%Y %H:%M}",
                "params": {"busy_until": self.busy_until.isoformat()},
            },
        )


class UnitUnavailable(DomainError):
    code = "unit_unavailable"
    status = 409


class BookingExpired(DomainError):
    code = "booking_expired"
    status = 409


class AlreadyCharged(DomainError):
    code = "already_charged"
    status = 409


class DuplicateSerial(DomainError):
    code = "duplicate_serial"
    status = 409


class DuplicateEmail(DomainError):
    code = "duplicate_email"
    status = 409


class InsufficientFunds(DomainError):
    code = "insufficient_funds"
    status = 422


class IdempotencyKeyReused(DomainError):
    code = "idempotency_key_reused"
    status = 409


class StaleData(DomainError):
    code = "stale_data"
    status = 409


# --- инфраструктура ---------------------------------------------------------


class DatabaseUnavailable(TransientError):
    code = "database_unavailable"


class CacheUnavailable(TransientError):
    code = "cache_unavailable"


class StorageUnavailable(TransientError):
    code = "storage_unavailable"


class QueueUnavailable(TransientError):
    code = "queue_unavailable"


class PaymentUnavailable(TransientError):
    code = "payment_unavailable"


class NotificationError(TransientError):
    code = "notification_failed"


class CircuitOpen(TransientError):
    code = "dependency_unavailable"


class IntegrationError(InfrastructureError):
    """Внешняя система ответила неожиданно; повтор не поможет."""

    code = "integration_error"
    status = 502


class ConfigurationError(InfrastructureError):
    """Неверные настройки: повтор бесполезен, нужен человек."""

    code = "internal_error"
    status = 500


ERROR_CATALOG: dict[str, tuple[int, str]] = {
    "validation_failed": (400, "Запрос содержит некорректные данные"),
    "unsupported_media_type": (415, "Неподдерживаемый тип содержимого"),
    "payload_too_large": (413, "Тело запроса слишком велико"),
    "unauthenticated": (401, "Требуется авторизация"),
    "token_expired": (401, "Срок действия токена истёк"),
    "invalid_token": (401, "Токен недействителен"),
    "invalid_credentials": (401, "Неверный логин или пароль"),
    "permission_denied": (403, "Недостаточно прав"),
    "not_found": (404, "Ресурс не найден"),
    "invalid_transition": (409, "Недопустимый переход статуса"),
    "invalid_period": (422, "Некорректный интервал"),
    "booking_overlap": (409, "Выбранный интервал уже занят"),
    "unit_unavailable": (409, "Экземпляр выведен из оборота"),
    "booking_expired": (409, "Срок удержания брони истёк"),
    "already_charged": (409, "Начисление уже выполнено"),
    "duplicate_serial": (409, "Серийный номер уже используется"),
    "duplicate_email": (409, "Адрес уже зарегистрирован"),
    "insufficient_funds": (422, "Недостаточно средств"),
    "idempotency_key_reused": (409, "Ключ идемпотентности использован с другими данными"),
    "stale_data": (409, "Данные изменились, обновите и повторите"),
    "rate_limited": (429, "Превышен лимит запросов"),
    "database_unavailable": (503, "База данных недоступна"),
    "cache_unavailable": (503, "Кеш недоступен"),
    "storage_unavailable": (503, "Хранилище файлов недоступно"),
    "queue_unavailable": (503, "Очередь задач недоступна"),
    "payment_unavailable": (503, "Платёжный шлюз недоступен"),
    "notification_failed": (503, "Сервис уведомлений недоступен"),
    "dependency_unavailable": (503, "Внешний сервис временно недоступен"),
    "integration_error": (502, "Внешний сервис ответил неожиданно"),
    "internal_error": (500, "Внутренняя ошибка сервиса"),
}
