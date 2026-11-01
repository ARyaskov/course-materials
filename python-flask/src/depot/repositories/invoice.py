"""Счета и их строки."""

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from depot.domain.access import Actor
from depot.domain.enums import InvoiceLineKind, InvoiceStatus, UserRole
from depot.domain.errors import NotFound
from depot.domain.ids import InvoiceId
from depot.domain.models import Booking, Invoice, InvoiceLine, Rental, Unit
from depot.repositories.errors import translate_integrity_error


class InvoiceRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def visible_for(self, actor: Actor):
        stmt = select(Invoice)
        if actor.role is UserRole.ADMIN:
            return stmt
        stmt = stmt.join(Booking, Invoice.booking_id == Booking.id)
        if actor.role is UserRole.OPERATOR:
            return stmt.join(Unit, Booking.unit_id == Unit.id).where(
                Unit.station_id == actor.station_id
            )
        return stmt.where(Booking.user_id == actor.id)

    def get(self, invoice_id: InvoiceId) -> Invoice:
        stmt = (
            select(Invoice)
            .options(selectinload(Invoice.lines))
            .where(Invoice.id == invoice_id)
        )
        invoice = self._session.scalars(stmt).unique().one_or_none()
        if invoice is None:
            raise NotFound(f"счёт {invoice_id} не найден")
        return invoice

    def for_booking(self, booking_id) -> Invoice | None:
        stmt = (
            select(Invoice)
            .options(selectinload(Invoice.lines))
            .where(Invoice.booking_id == booking_id)
        )
        return self._session.scalars(stmt).unique().one_or_none()

    def create_for(self, booking: Booking) -> Invoice:
        """Счёт за аренду по сумме, зафиксированной при бронировании."""
        invoice = Invoice(
            booking_id=booking.id,
            status=InvoiceStatus.ISSUED,
            total=booking.total,
            currency=booking.currency,
            issued_at=booking.updated_at,
        )
        self._session.add(invoice)
        self._session.flush()

        self._session.add(
            InvoiceLine(
                invoice_id=invoice.id,
                kind=InvoiceLineKind.RENTAL,
                day=None,
                amount=booking.total,
                description="Аренда по брони",
            )
        )
        self._session.flush()
        return invoice

    def void_for(self, booking: Booking) -> None:
        invoice = self.for_booking(booking.id)
        if invoice is not None and invoice.status is not InvoiceStatus.PAID:
            invoice.status = InvoiceStatus.VOID

    def add_late_fee(
        self, rental: Rental, day: date, amount: Decimal, description: str
    ) -> bool:
        """Начислить штраф за сутки просрочки.

        Уникальное ограничение по тройке «счёт, вид, день» делает двойное
        начисление невозможным даже при гонке двух воркеров: нарушение
        перехватывается, и задача завершается молча.
        """
        invoice = self.for_booking(rental.booking_id)
        if invoice is None:
            return False

        line = InvoiceLine(
            invoice_id=invoice.id,
            kind=InvoiceLineKind.LATE_FEE,
            day=datetime.combine(day, datetime.min.time()).replace(
                tzinfo=rental.due_at.tzinfo
            ),
            amount=amount,
            description=description,
        )
        self._session.add(line)
        try:
            self._session.flush()
        except IntegrityError as exc:
            if "uq_invoice_lines_kind_day" in str(exc.orig):
                self._session.rollback()
                return False
            raise translate_integrity_error(exc) from exc

        invoice.total = invoice.total + amount
        self._session.flush()
        return True

    def late_fee_exists(self, rental: Rental, day: date) -> bool:
        invoice = self.for_booking(rental.booking_id)
        if invoice is None:
            return False
        stmt = select(InvoiceLine.id).where(
            InvoiceLine.invoice_id == invoice.id,
            InvoiceLine.kind == InvoiceLineKind.LATE_FEE,
        )
        return self._session.scalar(stmt) is not None
