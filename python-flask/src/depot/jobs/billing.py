"""Начисление штрафов за просрочку.

Задача идёт порциями и рассчитана на несколько параллельных воркеров:
выборка берёт строки с пропуском занятых, а уникальное ограничение
«счёт, вид, день» не даёт начислить за одни сутки дважды.
"""

import logging

from depot.domain.money import Money
from depot.domain.pricing import late_fee
from depot.jobs.context import component, job
from depot.services.uow import make_uow

log = logging.getLogger(__name__)

#: размер порции: больше — длинная транзакция и заметная блокировка,
#: меньше — лишние обходы очереди
BATCH_SIZE = 100


@job
def charge_late_fees(limit: int = BATCH_SIZE) -> int:
    """Начислить штрафы по просроченным арендам.

    Повторный запуск за те же сутки безопасен: строка счёта уникальна
    по тройке «счёт, вид, день», и попытка вставить дубль отсекается базой.
    """
    clock = component("clock")
    now = clock.now()
    charged = 0

    with make_uow() as uow:
        overdue = uow.rentals.overdue_batch(now, limit)

        for rental in overdue:
            model = rental.booking.unit.model
            fee = late_fee(Money(model.daily_rate, model.currency), rental.due_at, now)
            if fee.amount <= 0:
                continue

            added = uow.invoices.add_late_fee(
                rental,
                day=now.date(),
                amount=fee.amount,
                description=f"Просрочка возврата, {now:%d.%m.%Y}",
            )
            if added:
                charged += 1

    if charged:
        log.info("late fees charged", extra={"count": charged})
    return charged


@job
def release_expired_holds(limit: int = BATCH_SIZE) -> int:
    """Возврат удержаний по отменённым броням.

    Деньги клиента не должны оставаться замороженными из-за того, что
    отмена прошла, а обращение к платёжному шлюзу — нет.
    """
    from depot.domain.enums import BookingStatus
    from depot.domain.models import Booking

    payment = component("payment")
    released = 0

    with make_uow() as uow:
        stale = (
            uow.session.query(Booking)
            .filter(
                Booking.status == BookingStatus.CANCELLED,
                Booking.payment_hold_id.is_not(None),
            )
            .limit(limit)
            .all()
        )
        for booking in stale:
            hold_id = booking.payment_hold_id
            # ключ идемпотентности выводится из данных, а не генерируется:
            # повтор задачи должен дать шлюзу тот же ключ
            payment.release(hold_id, idempotency_key=f"release:{booking.id}")
            booking.payment_hold_id = None
            released += 1

    return released
