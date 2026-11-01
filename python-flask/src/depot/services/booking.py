"""Сценарии работы с бронями.

Сервис координирует шаги, но не выполняет их сам: правила и расчёты живут
в домене, доступ к данным — в репозиториях, отложенная работа — в очереди.

Ни кодов состояния, ни объекта запроса, ни SQL здесь нет: сервис одинаково
вызывается из HTTP, из очереди и из командной строки.
"""

import logging
from collections.abc import Callable
from datetime import datetime

from depot.domain.access import check_booking_access
from depot.domain.enums import BookingAction, BookingStatus, UnitCondition
from depot.domain.errors import (
    BookingExpired,
    NotFound,
    TransientError,
    UnitUnavailable,
)
from depot.domain.ids import BookingId
from depot.domain.models import Booking
from depot.domain.money import Money
from depot.domain.pricing import rental_total
from depot.domain.rules import (
    HOLD_DURATION,
    INSPECTION_BUFFER,
    check_duration,
    check_transition,
)
from depot.repositories.booking import Page
from depot.services.commands import (
    BookingFilters,
    CallContext,
    CancelBookingCommand,
    ConfirmBookingCommand,
    CreateBookingCommand,
    UpdateBookingCommand,
)
from depot.services.protocols import Clock, Notifier, PaymentGateway, TaskQueue
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

EXPIRE_TASK = "depot.jobs.bookings.expire_booking"
CONFIRMATION_TASK = "depot.jobs.notifications.send_confirmation"


class BookingService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        queue: TaskQueue,
        clock: Clock,
        notifier: Notifier,
        payment: PaymentGateway,
    ) -> None:
        self._uow_factory = uow_factory
        self._queue = queue
        self._clock = clock
        self._notifier = notifier
        self._payment = payment

    def create(self, command: CreateBookingCommand, ctx: CallContext) -> Booking:
        now = self._clock.now()
        check_duration(command.period)

        with self._uow_factory() as uow:
            unit = uow.units.get(command.unit_id)
            if unit.condition is UnitCondition.RETIRED:
                raise UnitUnavailable("экземпляр выведен из оборота")

            conflicts = uow.bookings.overlapping(
                command.unit_id, command.period, INSPECTION_BUFFER
            )
            if conflicts:
                from depot.domain.errors import BookingOverlap

                raise BookingOverlap(busy_until=max(c.ends_at for c in conflicts))

            total = rental_total(
                Money(unit.model.daily_rate, unit.model.currency),
                command.period,
                unit.station.timezone,
            )

            booking = Booking(
                user_id=command.user_id,
                unit_id=command.unit_id,
                status=BookingStatus.PENDING,
                starts_at=command.period.starts_at,
                ends_at=command.period.ends_at,
                total=total.amount,
                currency=total.currency,
                note=command.note,
                hold_expires_at=now + HOLD_DURATION,
            )
            uow.bookings.add(booking)
            booking_id = booking.id
            hold_expires_at = booking.hold_expires_at

        # Постановка за границами транзакции: очередь не откатывается вместе
        # с ней. Окно закрывает периодическая задача expire_stale_holds.
        self._schedule(hold_expires_at, EXPIRE_TASK, booking_id, ctx)
        return booking

    def get(self, booking_id: BookingId, ctx: CallContext) -> Booking:
        with self._uow_factory() as uow:
            booking = uow.bookings.get(booking_id)
            check_booking_access(ctx.actor, booking, BookingAction.VIEW)
            return booking

    def search(
        self,
        filters: BookingFilters,
        ctx: CallContext,
        *,
        sort: str = "-created_at",
        page: int = 1,
        per_page: int = 20,
    ) -> Page[Booking]:
        with self._uow_factory() as uow:
            return uow.bookings.search(
                ctx.actor, filters, sort=sort, page=page, per_page=per_page
            )

    def confirm(self, command: ConfirmBookingCommand, ctx: CallContext) -> Booking:
        with self._uow_factory() as uow:
            booking = uow.bookings.get(command.booking_id)
            check_booking_access(ctx.actor, booking, BookingAction.CONFIRM)
            check_transition(booking.status, BookingStatus.CONFIRMED)

            if booking.hold_expires_at and booking.hold_expires_at < self._clock.now():
                raise BookingExpired("срок удержания брони истёк")

            booking.status = BookingStatus.CONFIRMED
            booking.hold_expires_at = None
            booking.notification_pending = True
            uow.invoices.create_for(booking)
            booking_id = booking.id

        self._enqueue(CONFIRMATION_TASK, booking_id, ctx)
        return booking

    def cancel(self, command: CancelBookingCommand, ctx: CallContext) -> Booking:
        with self._uow_factory() as uow:
            booking = uow.bookings.get(command.booking_id)
            check_booking_access(ctx.actor, booking, BookingAction.CANCEL)
            check_transition(booking.status, BookingStatus.CANCELLED)

            booking.status = BookingStatus.CANCELLED
            booking.cancel_reason = command.reason
            booking.hold_expires_at = None
            uow.invoices.void_for(booking)
            return booking

    def update(self, command: UpdateBookingCommand, ctx: CallContext) -> Booking:
        from depot.services.commands import UNSET

        with self._uow_factory() as uow:
            booking = uow.bookings.get(command.booking_id)
            check_booking_access(ctx.actor, booking, BookingAction.UPDATE)
            check_transition(booking.status, booking.status)

            if command.note is not UNSET:
                booking.note = command.note  # type: ignore[assignment]

            if command.period is not UNSET and command.period is not None:
                check_duration(command.period)
                conflicts = [
                    c
                    for c in uow.bookings.overlapping(
                        booking.unit_id, command.period, INSPECTION_BUFFER
                    )
                    if c.id != booking.id
                ]
                if conflicts:
                    from depot.domain.errors import BookingOverlap

                    raise BookingOverlap(busy_until=max(c.ends_at for c in conflicts))
                booking.starts_at = command.period.starts_at
                booking.ends_at = command.period.ends_at

            return booking

    def expire(self, booking_id: BookingId) -> Booking | None:
        """Истечение удержания.

        Три проверки предусловий делают операцию идемпотентной: повторный
        вызов обнаруживает достигнутое состояние и завершается.
        """
        with self._uow_factory() as uow:
            booking = uow.bookings.find(booking_id)
            if booking is None:
                return None
            if booking.status is not BookingStatus.PENDING:
                return booking
            if booking.hold_expires_at is None or booking.hold_expires_at > self._clock.now():
                return booking

            booking.status = BookingStatus.EXPIRED
            return booking

    def expire_stale(self, limit: int = 200) -> int:
        """Периодическая подчистка просроченных удержаний.

        Точечные задачи ставятся вне транзакции и теряются при падении
        процесса между фиксацией и постановкой. Этот проход восстанавливает
        состояние из данных, а не из очереди, и потому не зависит от неё.

        Каждая бронь обрабатывается своей транзакцией: одна проблемная строка
        не должна отменять работу по остальным.
        """
        with self._uow_factory() as uow:
            stale = uow.bookings.expire_stale_ids(self._clock.now(), limit)

        released = 0
        for booking_id in stale:
            booking = self.expire(booking_id)
            if booking is not None and booking.status is BookingStatus.EXPIRED:
                released += 1
        return released

    def _schedule(
        self, when: datetime | None, task: str, booking_id: BookingId, ctx: CallContext
    ) -> None:
        if when is None:
            return
        try:
            self._queue.enqueue_at(
                when, task, {"booking_id": str(booking_id), "request_id": ctx.request_id}
            )
        except TransientError:
            # Недоступность очереди не отменяет операцию: состояние
            # восстанавливается периодической задачей из данных.
            log.warning("failed to schedule %s", task, extra={"booking_id": str(booking_id)})

    def _enqueue(self, task: str, booking_id: BookingId, ctx: CallContext) -> None:
        try:
            self._queue.enqueue(
                task, {"booking_id": str(booking_id), "request_id": ctx.request_id}
            )
        except TransientError:
            log.warning("failed to enqueue %s", task, extra={"booking_id": str(booking_id)})
