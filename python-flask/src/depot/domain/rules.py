"""Правила предметной области: константы, переходы статусов, пересечения.

Модуль не импортирует ничего из проекта, кроме соседей по `domain`, поэтому
проверяется тестами без базы и без приложения.
"""

from collections.abc import Iterable
from datetime import timedelta
from typing import Final

from depot.domain.enums import BookingStatus
from depot.domain.errors import InvalidTransition
from depot.domain.period import Period

#: время на осмотр и зарядку между арендами одного экземпляра
INSPECTION_BUFFER: Final = timedelta(hours=2)

#: сколько экземпляр удерживается за неподтверждённой бронью
HOLD_DURATION: Final = timedelta(hours=1)

#: предельная длительность одной брони
MAX_BOOKING_DURATION: Final = timedelta(days=30)

#: доля суточной ставки, начисляемая за час просрочки
LATE_FEE_HOURS_PER_DAY: Final = 12

TRANSITIONS: Final[dict[BookingStatus, frozenset[BookingStatus]]] = {
    BookingStatus.PENDING: frozenset(
        {BookingStatus.CONFIRMED, BookingStatus.CANCELLED, BookingStatus.EXPIRED}
    ),
    BookingStatus.CONFIRMED: frozenset(
        {BookingStatus.CANCELLED, BookingStatus.COMPLETED}
    ),
    BookingStatus.CANCELLED: frozenset(),
    BookingStatus.COMPLETED: frozenset(),
    BookingStatus.EXPIRED: frozenset(),
}


def check_transition(current: BookingStatus, target: BookingStatus) -> None:
    """Проверить допустимость перехода статуса.

    Таблица переходов — одновременно документация и проверка: добавление
    статуса требует явного решения о переходах из него и в него.
    """
    if target not in TRANSITIONS[current]:
        raise InvalidTransition(f"переход {current} → {target} запрещён")


def check_duration(period: Period) -> None:
    if period.duration > MAX_BOOKING_DURATION:
        from depot.domain.errors import InvalidPeriod

        raise InvalidPeriod(
            f"интервал не может превышать {MAX_BOOKING_DURATION.days} суток"
        )


def has_conflict(
    requested: Period,
    existing: Iterable[Period],
    buffer: timedelta = INSPECTION_BUFFER,
) -> bool:
    """Пересекается ли запрошенный интервал с одним из существующих."""
    return any(requested.overlaps(period, buffer) for period in existing)
