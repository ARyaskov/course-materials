"""Аренды и акты повреждения."""

from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload, selectinload

from depot.domain.access import Actor
from depot.domain.enums import UserRole
from depot.domain.errors import NotFound
from depot.domain.ids import RentalId
from depot.domain.models import Booking, DamagePhoto, DamageReport, Rental, Unit
from depot.repositories.booking import Page
from depot.repositories.errors import translate_integrity_error


class RentalRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def visible_for(self, actor: Actor):
        stmt = select(Rental)
        if actor.role is UserRole.ADMIN:
            return stmt
        stmt = stmt.join(Booking, Rental.booking_id == Booking.id)
        if actor.role is UserRole.OPERATOR:
            return stmt.join(Unit, Booking.unit_id == Unit.id).where(
                Unit.station_id == actor.station_id
            )
        return stmt.where(Booking.user_id == actor.id)

    def find(self, rental_id: RentalId) -> Rental | None:
        """Загружает аренду с бронью, экземпляром и актами повреждения.

        Связь «ко многим» грузится отдельным запросом: соединение размножило бы
        строки и сломало ограничение выборки.
        """
        stmt = (
            select(Rental)
            .options(
                joinedload(Rental.booking).joinedload(Booking.unit).joinedload(Unit.model),
                selectinload(Rental.damage_reports),
            )
            .where(Rental.id == rental_id)
        )
        return self._session.scalars(stmt).unique().one_or_none()

    def get(self, rental_id: RentalId) -> Rental:
        rental = self.find(rental_id)
        if rental is None:
            raise NotFound(f"аренда {rental_id} не найдена")
        return rental

    def search(
        self,
        actor: Actor,
        *,
        overdue_only: bool = False,
        page: int = 1,
        per_page: int = 20,
    ) -> Page[Rental]:
        """Список аренд с учётом видимости.

        Счёт берётся с того же запроса до применения загрузок связей:
        joinedload по связи «ко многим» размножил бы строки и завысил итог.
        """
        stmt = self.visible_for(actor)
        if overdue_only:
            stmt = stmt.where(
                Rental.returned_at.is_(None), Rental.due_at < datetime.now(UTC)
            )

        total = (
            self._session.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        )

        stmt = (
            stmt.options(
                joinedload(Rental.booking).joinedload(Booking.unit).joinedload(Unit.model)
            )
            .order_by(Rental.issued_at.desc(), Rental.id.desc())
            .limit(per_page)
            .offset((page - 1) * per_page)
        )
        items = list(self._session.scalars(stmt).unique().all())
        return Page(items=items, total=total, page=page, per_page=per_page)

    def overdue_batch(self, as_of: datetime, limit: int) -> list[Rental]:
        """Просроченные аренды порцией, с пропуском занятых строк."""
        stmt = (
            select(Rental)
            .options(joinedload(Rental.booking).joinedload(Booking.unit).joinedload(Unit.model))
            .where(Rental.returned_at.is_(None), Rental.due_at < as_of)
            .order_by(Rental.due_at)
            .limit(limit)
            .with_for_update(skip_locked=True, of=Rental)
        )
        return list(self._session.scalars(stmt).unique().all())

    def add(self, rental: Rental) -> None:
        self._session.add(rental)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise translate_integrity_error(exc) from exc

    def add_damage_report(
        self, rental: Rental, report: DamageReport, photos: Sequence[DamagePhoto]
    ) -> DamageReport:
        self._session.add(report)
        self._session.flush()
        for photo in photos:
            photo.report_id = report.id
            self._session.add(photo)
        self._session.flush()
        return report
