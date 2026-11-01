"""Выдача и приём оборудования.

Возврат — самая связная операция проекта: он закрывает аренду, переводит
бронь в завершённые, меняет состояние экземпляра, при просрочке добавляет
строку в счёт и при повреждении создаёт акт. Всё это одна транзакция:
возврат без счёта и счёт без возврата одинаково плохи.
"""

import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from uuid import UUID

from depot.domain.access import check_rental_access
from depot.domain.enums import (
    BookingStatus,
    Permission,
    RentalAction,
    UnitCondition,
)
from depot.domain.errors import InvalidTransition
from depot.domain.ids import BookingId, RentalId
from depot.domain.models import DamageReport, Rental
from depot.domain.money import Money
from depot.domain.permissions import require_permission
from depot.domain.pricing import late_fee
from depot.domain.rules import check_transition
from depot.repositories.booking import Page
from depot.services.commands import CallContext, IssueRentalCommand, ReturnRentalCommand
from depot.services.protocols import Clock, FileStorage, PaymentGateway, TaskQueue
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

RETURN_TASK = "depot.jobs.notifications.send_return_receipt"

#: состояния, при которых экземпляр нельзя выдать
BLOCKING_CONDITIONS = frozenset({UnitCondition.RETIRED, UnitCondition.NEEDS_REPAIR})

#: доля залога, выше которой повреждение считается серьёзным: такой
#: экземпляр не возвращается в оборот сразу, а уходит в ремонт
SEVERE_DAMAGE_RATIO = Decimal("0.3")


@dataclass(frozen=True, slots=True)
class ReturnResult:
    """Результат возврата.

    Отдельный объект, а не кортеж: у полей есть имена, и добавление
    четвёртого не ломает распаковку у вызывающих.
    """

    rental: Rental
    late_fee_amount: Decimal
    damage_report_id: UUID | None


class RentalService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        queue: TaskQueue,
        clock: Clock,
        storage: FileStorage,
        payment: PaymentGateway,
    ) -> None:
        self._uow_factory = uow_factory
        self._queue = queue
        self._clock = clock
        self._storage = storage
        self._payment = payment

    def issue(self, command: IssueRentalCommand, ctx: CallContext) -> Rental:
        """Выдача по подтверждённой брони.

        Статус брони при выдаче не меняется: она остаётся подтверждённой
        до возврата. Факт выдачи хранится отдельной записью, и это позволяет
        отличить «оборудование у клиента» от «бронь оформлена».
        """
        require_permission(ctx.actor, Permission.RENTAL_ISSUE)

        with self._uow_factory() as uow:
            booking = uow.bookings.get(BookingId(command.booking_id))
            if booking.status is not BookingStatus.CONFIRMED:
                raise InvalidTransition(
                    f"выдача возможна только по подтверждённой брони, статус: {booking.status}"
                )

            unit = uow.units.get(booking.unit_id)
            if unit.condition in BLOCKING_CONDITIONS:
                raise InvalidTransition(f"экземпляр в состоянии {unit.condition}")

            rental = Rental(
                booking_id=booking.id,
                issued_at=self._clock.now(),
                # срок возврата берётся из брони, а не из момента выдачи:
                # опоздание клиента к началу не продлевает аренду
                due_at=booking.ends_at,
                issued_by=ctx.actor.id,
            )
            uow.rentals.add(rental)

            log.info(
                "rental issued",
                extra={"rental_id": str(rental.id), "booking_id": str(booking.id)},
            )
            return rental

    def get(self, rental_id: RentalId, ctx: CallContext) -> Rental:
        with self._uow_factory() as uow:
            rental = uow.rentals.get(rental_id)
            check_rental_access(ctx.actor, rental, RentalAction.VIEW)
            return rental

    def search(
        self,
        ctx: CallContext,
        *,
        overdue_only: bool = False,
        page: int = 1,
        per_page: int = 20,
    ) -> Page[Rental]:
        with self._uow_factory() as uow:
            return uow.rentals.search(
                ctx.actor, overdue_only=overdue_only, page=page, per_page=per_page
            )

    def accept_return(
        self, command: ReturnRentalCommand, ctx: CallContext
    ) -> ReturnResult:
        require_permission(ctx.actor, Permission.RENTAL_RETURN)

        with self._uow_factory() as uow:
            rental = uow.rentals.get(command.rental_id)
            check_rental_access(ctx.actor, rental, RentalAction.RETURN)

            if rental.returned_at is not None:
                # повторный приём — не опечатка оператора, а гонка двух
                # приёмщиков; состояние уже достигнуто, менять нечего
                raise InvalidTransition("аренда уже закрыта")

            now = self._clock.now()
            rental.returned_at = now

            booking = rental.booking
            check_transition(booking.status, BookingStatus.COMPLETED)
            booking.status = BookingStatus.COMPLETED

            unit = booking.unit
            fee = late_fee(
                Money(unit.model.daily_rate, unit.model.currency), rental.due_at, now
            )
            if fee.amount > 0:
                uow.invoices.add_late_fee(
                    rental,
                    day=now.date(),
                    amount=fee.amount,
                    description=f"Просрочка возврата до {now:%d.%m.%Y %H:%M}",
                )

            report_id = None
            if command.damage_description:
                report = self._build_report(command, unit.model.deposit)
                uow.rentals.add_damage_report(rental, report, photos=())
                report_id = report.id
                # серьёзное повреждение выводит экземпляр из оборота: иначе
                # он попадёт в следующую бронь в тот же день
                unit.condition = (
                    UnitCondition.NEEDS_REPAIR
                    if report.severity == "major"
                    else command.condition
                )
            else:
                unit.condition = command.condition

            result = ReturnResult(
                rental=rental,
                late_fee_amount=fee.amount,
                damage_report_id=report_id,
            )

        # уведомление ставится после фиксации транзакции: иначе письмо
        # о возврате уйдёт даже при откате
        self._queue.enqueue(RETURN_TASK, {"rental_id": str(command.rental_id)})
        return result

    def store_photo(
        self,
        rental_id: RentalId,
        data: bytes,
        media_type: str,
        original_name: str,
        ctx: CallContext,
    ) -> str:
        """Сохранение фотографии повреждения.

        Имя файла придумывает сервер: имя из запроса содержит что угодно —
        переходы по каталогам, совпадения с чужими ключами, управляющие
        символы. Оригинальное имя остаётся метаданными записи.
        """
        from depot.infrastructure.storage import storage_key

        with self._uow_factory() as uow:
            rental = uow.rentals.get(rental_id)
            check_rental_access(ctx.actor, rental, RentalAction.RETURN)

        key = storage_key(original_name, media_type, prefix=f"damage/{rental_id}")
        self._storage.put(key, data, content_type=media_type)
        return key

    def overdue_ids(self, as_of: datetime, limit: int) -> list[RentalId]:
        """Порция просроченных аренд для фоновой задачи.

        Наружу отдаются идентификаторы, а не объекты: транзакция здесь
        закрывается, и работать с отсоединёнными экземплярами нельзя.
        """
        with self._uow_factory() as uow:
            return [r.id for r in uow.rentals.overdue_batch(as_of, limit)]

    @staticmethod
    def _build_report(command: ReturnRentalCommand, deposit: Decimal) -> DamageReport:
        cost = command.damage_cost or Decimal("0")
        severity = "major" if cost > deposit * SEVERE_DAMAGE_RATIO else "minor"
        return DamageReport(
            description=command.damage_description or "",
            severity=severity,
            estimated_cost=cost,
        )
