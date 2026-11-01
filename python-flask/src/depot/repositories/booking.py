"""Доступ к данным броней.

Интерфейс на языке домена: «найти пересекающиеся брони», а не «выполнить
select с четырьмя условиями». SQL не виден за пределами этого слоя.

Пара `find` / `get` — конвенция проекта: первый возвращает None, второй
поднимает исключение.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import timedelta
from typing import Generic, TypeVar

from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from depot.domain.access import Actor
from depot.domain.enums import ACTIVE_BOOKING_STATUSES, BookingStatus, UserRole
from depot.domain.errors import NotFound
from depot.domain.ids import BookingId, UnitId
from depot.domain.models import Booking, Unit
from depot.domain.period import Period
from depot.repositories.errors import translate_integrity_error
from depot.services.commands import BookingFilters

T = TypeVar("T")


@dataclass(frozen=True, slots=True)
class Page(Generic[T]):
    items: list[T]
    total: int
    page: int
    per_page: int


SORTABLE = {
    "created_at": Booking.created_at,
    "starts_at": Booking.starts_at,
}


class BookingRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def visible_for(self, actor: Actor) -> Select:
        """Заготовка запроса с применённым правилом видимости.

        Вызывается всеми методами выборки. Дублирование строки предпочтительнее
        конструкции, которая может не сработать: забытый вызов — утечка данных.
        """
        stmt = select(Booking)
        if actor.role is UserRole.ADMIN:
            return stmt
        if actor.role is UserRole.OPERATOR:
            return stmt.join(Unit, Booking.unit_id == Unit.id).where(
                Unit.station_id == actor.station_id
            )
        return stmt.where(Booking.user_id == actor.id)

    def find(self, booking_id: BookingId) -> Booking | None:
        """Загружает бронь с экземпляром и моделью; None, если не найдена."""
        stmt = (
            select(Booking)
            .options(joinedload(Booking.unit).joinedload(Unit.model))
            .where(Booking.id == booking_id)
        )
        return self._session.scalars(stmt).unique().one_or_none()

    def get(self, booking_id: BookingId) -> Booking:
        """Загружает бронь с экземпляром и моделью; NotFound, если не найдена."""
        booking = self.find(booking_id)
        if booking is None:
            raise NotFound(f"бронь {booking_id} не найдена")
        return booking

    def overlapping(
        self,
        unit_id: UnitId,
        period: Period,
        buffer: timedelta = timedelta(),
    ) -> list[Booking]:
        """Активные брони экземпляра, пересекающиеся с интервалом."""
        stmt = select(Booking).where(
            Booking.unit_id == unit_id,
            Booking.status.in_(ACTIVE_BOOKING_STATUSES),
            Booking.starts_at < period.ends_at + buffer,
            Booking.ends_at + buffer > period.starts_at,
        )
        return list(self._session.scalars(stmt).all())

    def search(
        self,
        actor: Actor,
        filters: BookingFilters,
        *,
        sort: str = "-created_at",
        page: int = 1,
        per_page: int = 20,
    ) -> Page[Booking]:
        """Страница броней, видимых актору.

        Загружает связи unit → model. Подсчёт выполняется по тем же условиям,
        иначе общее количество не совпадёт с фильтрацией.
        """
        stmt = self._apply_filters(self.visible_for(actor), filters)

        total = (
            self._session.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        )

        stmt = (
            self._apply_sort(stmt, sort)
            .options(joinedload(Booking.unit).joinedload(Unit.model))
            .limit(per_page)
            .offset((page - 1) * per_page)
        )
        items = list(self._session.scalars(stmt).unique().all())
        return Page(items=items, total=total, page=page, per_page=per_page)

    def by_ids(self, actor: Actor, ids: Sequence[BookingId]) -> list[Booking]:
        """Только существующие и видимые: разница в количестве информативна."""
        stmt = self.visible_for(actor).where(Booking.id.in_(ids))
        return list(self._session.scalars(stmt).unique().all())

    def add(self, booking: Booking) -> None:
        """Вставка с преобразованием нарушений целостности в доменные ошибки.

        Второй рубеж после проверки пересечений в сервисе: ограничение
        исключения ловит гонку, от которой проверка в коде не спасает.
        """
        self._session.add(booking)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise translate_integrity_error(exc) from exc

    def expire_stale_ids(self, now, limit: int) -> list[BookingId]:
        """Идентификаторы просроченных удержаний с пропуском занятых строк.

        `skip_locked` позволяет запускать задачу в нескольких экземплярах:
        они разберут разные порции, не мешая друг другу.
        """
        stmt = (
            select(Booking.id)
            .where(
                Booking.status == BookingStatus.PENDING,
                Booking.hold_expires_at.is_not(None),
                Booking.hold_expires_at < now,
            )
            .limit(limit)
            .with_for_update(skip_locked=True)
        )
        return list(self._session.scalars(stmt).all())

    def _apply_filters(self, stmt: Select, f: BookingFilters) -> Select:
        if f.status is not None:
            stmt = stmt.where(Booking.status == f.status)
        if f.unit_id is not None:
            stmt = stmt.where(Booking.unit_id == f.unit_id)
        if f.starts_after is not None:
            stmt = stmt.where(Booking.starts_at >= f.starts_after)
        if f.starts_before is not None:
            stmt = stmt.where(Booking.starts_at <= f.starts_before)
        if f.station_id is not None:
            stmt = stmt.where(
                Booking.unit_id.in_(
                    select(Unit.id).where(Unit.station_id == f.station_id)
                )
            )
        return stmt

    def _apply_sort(self, stmt: Select, sort: str) -> Select:
        column = SORTABLE[sort.lstrip("-")]
        ordering = column.desc() if sort.startswith("-") else column.asc()
        # уникальное поле последним ключом: без него страницы «плавают»
        return stmt.order_by(ordering, Booking.id.desc())
