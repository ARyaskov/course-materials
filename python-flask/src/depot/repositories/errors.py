"""Преобразование ошибок целостности в доменные.

Имя ограничения в тексте ошибки — единственный надёжный признак того, какое
правило нарушено. Именно поэтому имена задаются соглашением в `extensions.py`,
а не отдаются на откуп базе: они предсказуемы и одинаковы на всех стендах.
"""

from collections.abc import Callable

from sqlalchemy.exc import IntegrityError, OperationalError

from depot.domain.errors import (
    AlreadyCharged,
    BookingOverlap,
    DatabaseUnavailable,
    DepotError,
    DuplicateEmail,
    DuplicateSerial,
    InfrastructureError,
    InvalidPeriod,
)

CONSTRAINT_ERRORS: dict[str, Callable[[], DepotError]] = {
    "bookings_no_overlap": lambda: BookingOverlap("выбранный интервал уже занят"),
    "uq_units_serial": lambda: DuplicateSerial("серийный номер уже используется"),
    "uq_users_email_lower": lambda: DuplicateEmail("адрес уже зарегистрирован"),
    "uq_invoice_lines_kind_day": lambda: AlreadyCharged("начисление уже выполнено"),
    "ck_bookings_period_valid": lambda: InvalidPeriod("некорректный интервал"),
    "ck_bookings_total_non_negative": lambda: InvalidPeriod("сумма не может быть отрицательной"),
    "ck_users_operator_has_station": lambda: InvalidPeriod(
        "оператор должен быть привязан к станции"
    ),
}


def translate_integrity_error(exc: IntegrityError) -> DepotError:
    text = str(exc.orig)
    for name, factory in CONSTRAINT_ERRORS.items():
        if name in text:
            return factory()
    return InfrastructureError("нарушено ограничение целостности")


def translate_operational_error(exc: OperationalError) -> DepotError:
    return DatabaseUnavailable("база данных недоступна")
