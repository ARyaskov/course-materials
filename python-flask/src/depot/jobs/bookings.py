"""Задачи по броням."""

import logging
from uuid import UUID

from depot.domain.ids import BookingId
from depot.jobs.context import component, job
from depot.services.booking import BookingService
from depot.services.uow import make_uow

log = logging.getLogger(__name__)

#: сколько броней обрабатывается за один проход подчистки; ограничение
#: держит транзакцию короткой и не даёт задаче занять воркер надолго
SWEEP_BATCH = 200


def _service() -> BookingService:
    return BookingService(
        uow_factory=make_uow,
        queue=component("queue"),
        clock=component("clock"),
        notifier=component("notifier"),
        payment=component("payment"),
    )


@job
def expire_booking(booking_id: str) -> str:
    """Снятие удержания по одной брони.

    Задача идемпотентна: подтверждённую или уже отменённую бронь она
    оставляет как есть. Это обязательное свойство — очередь гарантирует
    доставку «хотя бы один раз», а не «ровно один раз».
    """
    booking = _service().expire(BookingId(UUID(booking_id)))
    if booking is None:
        # бронь удалена (например, при чистке тестовых данных) — не ошибка
        return "missing"
    return str(booking.status)


@job
def expire_stale_holds() -> int:
    """Периодическая подчистка просроченных удержаний.

    Страхует точечные задачи: постановка в очередь происходит вне
    транзакции, и при падении процесса между фиксацией и постановкой
    отложенная задача не создаётся. Раз в минуту этот проход закрывает
    оставшееся окно.
    """
    count = _service().expire_stale(limit=SWEEP_BATCH)
    if count:
        log.info("stale holds released", extra={"count": count})
    return count
