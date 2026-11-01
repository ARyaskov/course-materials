"""Счета.

Финансовый документ не редактируется и не удаляется: он аннулируется
и остаётся в истории. Иначе выручка за прошлый месяц меняется задним
числом, и сверка перестаёт сходиться.
"""

import logging
from collections.abc import Callable

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from depot.domain.enums import InvoiceStatus, Permission
from depot.domain.errors import InvalidTransition, NotFound
from depot.domain.ids import InvoiceId
from depot.domain.models import Invoice
from depot.domain.permissions import has_permission
from depot.repositories.booking import Page
from depot.services.commands import CallContext
from depot.services.protocols import Clock, PaymentGateway
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

#: аннулировать можно только то, что ещё не оплачено; возврат оплаченного
#: счёта — отдельная операция с движением денег
VOIDABLE = frozenset({InvoiceStatus.DRAFT, InvoiceStatus.ISSUED})


class BillingService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        clock: Clock,
        payment: PaymentGateway,
    ) -> None:
        self._uow_factory = uow_factory
        self._clock = clock
        self._payment = payment

    def search(
        self, ctx: CallContext, *, page: int = 1, per_page: int = 20
    ) -> Page[Invoice]:
        with self._uow_factory() as uow:
            stmt = uow.invoices.visible_for(ctx.actor)
            total = (
                uow.session.scalar(select(func.count()).select_from(stmt.subquery())) or 0
            )
            stmt = (
                stmt.options(selectinload(Invoice.lines))
                .order_by(Invoice.created_at.desc(), Invoice.id.desc())
                .limit(per_page)
                .offset((page - 1) * per_page)
            )
            items = list(uow.session.scalars(stmt).unique().all())
            return Page(items=items, total=total, page=page, per_page=per_page)

    def get(self, invoice_id: InvoiceId, ctx: CallContext) -> Invoice:
        """Счёт по идентификатору с учётом видимости.

        Проверка выполняется запросом, а не сравнением после загрузки:
        чужой счёт не должен появляться даже в памяти процесса.
        """
        with self._uow_factory() as uow:
            if has_permission(ctx.actor, Permission.INVOICE_READ_ANY):
                return uow.invoices.get(invoice_id)

            stmt = uow.invoices.visible_for(ctx.actor).where(Invoice.id == invoice_id)
            invoice = uow.session.scalars(
                stmt.options(selectinload(Invoice.lines))
            ).unique().one_or_none()
            if invoice is None:
                # 404, а не 403: ответ не должен подтверждать существование
                # чужого документа
                raise NotFound(f"счёт {invoice_id} не найден")
            return invoice

    def void(self, invoice_id: InvoiceId, reason: str, ctx: CallContext) -> Invoice:
        with self._uow_factory() as uow:
            invoice = uow.invoices.get(invoice_id)
            if invoice.status not in VOIDABLE:
                raise InvalidTransition(f"счёт в статусе {invoice.status} не аннулируется")

            invoice.status = InvoiceStatus.VOID
            log.info(
                "invoice voided",
                extra={
                    "invoice_id": str(invoice.id),
                    "actor_id": ctx.actor.id,
                    "reason": reason,
                },
            )
            return invoice

    def mark_paid(self, invoice_id: InvoiceId, ctx: CallContext) -> Invoice:
        """Отметка об оплате.

        Идемпотентна: повторное подтверждение от платёжного шлюза —
        обычное дело, и второй вызов не должен менять момент оплаты.
        """
        with self._uow_factory() as uow:
            invoice = uow.invoices.get(invoice_id)
            if invoice.status is InvoiceStatus.PAID:
                return invoice
            if invoice.status is InvoiceStatus.VOID:
                raise InvalidTransition("аннулированный счёт не оплачивается")

            invoice.status = InvoiceStatus.PAID
            invoice.paid_at = self._clock.now()
            return invoice
