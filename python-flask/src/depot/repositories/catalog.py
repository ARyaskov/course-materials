"""Каталог: модели оборудования, экземпляры, станции."""

from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from depot.domain.enums import UnitCondition
from depot.domain.errors import NotFound
from depot.domain.ids import ModelId, StationId, UnitId
from depot.domain.models import EquipmentModel, Station, Unit
from depot.repositories.booking import Page
from depot.repositories.errors import translate_integrity_error
from depot.services.commands import CatalogFilters

SORTABLE = {
    "title": EquipmentModel.title,
    "daily_rate": EquipmentModel.daily_rate,
}


class CatalogRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def find(self, model_id: ModelId) -> EquipmentModel | None:
        return self._session.get(EquipmentModel, model_id)

    def get(self, model_id: ModelId) -> EquipmentModel:
        model = self.find(model_id)
        if model is None:
            raise NotFound(f"модель {model_id} не найдена")
        return model

    def search(
        self,
        filters: CatalogFilters,
        *,
        sort: str = "title",
        page: int = 1,
        per_page: int = 20,
    ) -> Page[EquipmentModel]:
        stmt = self._apply_filters(select(EquipmentModel), filters)

        total = (
            self._session.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        )

        stmt = self._apply_sort(stmt, sort).limit(per_page).offset((page - 1) * per_page)
        items = list(self._session.scalars(stmt).all())
        return Page(items=items, total=total, page=page, per_page=per_page)

    def add(self, model: EquipmentModel) -> None:
        self._session.add(model)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise translate_integrity_error(exc) from exc

    def _apply_filters(self, stmt: Select, f: CatalogFilters) -> Select:
        if f.category is not None:
            stmt = stmt.where(EquipmentModel.category == f.category)
        if f.min_rate is not None:
            stmt = stmt.where(EquipmentModel.daily_rate >= f.min_rate)
        if f.max_rate is not None:
            stmt = stmt.where(EquipmentModel.daily_rate <= f.max_rate)
        if f.query is not None:
            # поиск по началу строки: шаблон с ведущим символом подстановки
            # индексом не покрывается; ограничение записано в контракте
            stmt = stmt.where(
                func.lower(EquipmentModel.title).like(f"{f.query.lower()}%")
            )
        if f.station_id is not None:
            stmt = stmt.where(
                EquipmentModel.id.in_(
                    select(Unit.model_id).where(Unit.station_id == f.station_id)
                )
            )
        return stmt

    def _apply_sort(self, stmt: Select, sort: str) -> Select:
        column = SORTABLE[sort.lstrip("-")]
        ordering = column.desc() if sort.startswith("-") else column.asc()
        return stmt.order_by(ordering, EquipmentModel.id.desc())


class UnitRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def find(self, unit_id: UnitId) -> Unit | None:
        """Загружает экземпляр с моделью и станцией."""
        stmt = (
            select(Unit)
            .options(joinedload(Unit.model), joinedload(Unit.station))
            .where(Unit.id == unit_id)
        )
        return self._session.scalars(stmt).unique().one_or_none()

    def get(self, unit_id: UnitId) -> Unit:
        unit = self.find(unit_id)
        if unit is None:
            raise NotFound(f"экземпляр {unit_id} не найден")
        return unit

    def for_station(self, station_id: StationId) -> list[Unit]:
        stmt = (
            select(Unit)
            .options(joinedload(Unit.model))
            .where(Unit.station_id == station_id, Unit.condition != UnitCondition.RETIRED)
            .order_by(Unit.serial)
        )
        return list(self._session.scalars(stmt).unique().all())

    def add(self, unit: Unit) -> None:
        self._session.add(unit)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise translate_integrity_error(exc) from exc


class StationRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def get(self, station_id: StationId) -> Station:
        station = self._session.get(Station, station_id)
        if station is None:
            raise NotFound(f"станция {station_id} не найдена")
        return station

    def active(self) -> list[Station]:
        stmt = select(Station).where(Station.is_active.is_(True)).order_by(Station.title)
        return list(self._session.scalars(stmt).all())

    def timezone_of(self, station_id: StationId) -> str:
        tz = self._session.scalar(
            select(Station.timezone).where(Station.id == station_id)
        )
        if tz is None:
            raise NotFound(f"станция {station_id} не найдена")
        return tz
