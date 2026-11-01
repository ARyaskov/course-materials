"""Уведомления.

Отправка вынесена из запроса намеренно: почтовый сервер отвечает за секунды
и иногда не отвечает вовсе. Пользователь не должен ждать этого, а операция
не должна откатываться из-за недоставленного письма.
"""

import logging
from uuid import UUID

from depot.domain.errors import NotificationError
from depot.jobs.context import component, job
from depot.services.uow import make_uow

log = logging.getLogger(__name__)

CONFIRMATION_SUBJECT = "Бронь подтверждена"
RETURN_SUBJECT = "Оборудование принято"


@job
def send_confirmation(booking_id: str) -> str:
    """Письмо о подтверждении брони.

    Флаг снимается только после успешной отправки: при падении задача
    будет повторена, и повторная попытка увидит его поднятым.
    """
    from depot.domain.models import Booking

    with make_uow() as uow:
        booking = uow.session.get(Booking, UUID(booking_id))
        if booking is None:
            return "missing"
        if not booking.notification_pending:
            # письмо уже отправлено: очередь доставляет «хотя бы один раз»,
            # и второй экземпляр задачи — норма, а не сбой
            return "already_sent"

        user = uow.users.get(booking.user_id)
        recipient, body = user.email, _confirmation_body(booking)

    notifier = component("notifier")
    try:
        notifier.send(recipient, CONFIRMATION_SUBJECT, body)
    except NotificationError:
        log.warning("confirmation not sent", extra={"booking_id": booking_id})
        raise

    with make_uow() as uow:
        fresh = uow.session.get(Booking, UUID(booking_id))
        if fresh is not None:
            fresh.notification_pending = False
    return "sent"


@job
def send_return_receipt(rental_id: str) -> str:
    from depot.domain.models import Rental

    with make_uow() as uow:
        rental = uow.rentals.find(UUID(rental_id))
        if rental is None:
            return "missing"
        user = uow.users.get(rental.booking.user_id)
        recipient = user.email
        body = (
            f"Оборудование по аренде {rental.id} принято "
            f"{rental.returned_at:%d.%m.%Y %H:%M}."
        )

    component("notifier").send(recipient, RETURN_SUBJECT, body)
    return "sent"


@job
def send_welcome(user_id: str) -> str:
    from depot.domain.models import User

    with make_uow() as uow:
        user = uow.session.get(User, int(user_id))
        if user is None:
            return "missing"
        recipient, name = user.email, user.full_name

    component("notifier").send(
        recipient,
        "Добро пожаловать в Depot",
        f"{name}, учётная запись создана. Каталог доступен в личном кабинете.",
    )
    return "sent"


def _confirmation_body(booking) -> str:  # type: ignore[no-untyped-def]
    return (
        f"Бронь {booking.id} подтверждена.\n"
        f"Период: {booking.starts_at:%d.%m.%Y %H:%M} — "
        f"{booking.ends_at:%d.%m.%Y %H:%M}.\n"
        f"Сумма: {booking.total} {booking.currency}."
    )
