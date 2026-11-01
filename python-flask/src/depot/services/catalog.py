"""Сценарии работы с каталогом.

Каталог читают гораздо чаще, чем меняют, поэтому здесь появляется кеш.
Он не обязателен: `ResilientCache` превращает недоступность Redis в промах,
и сервис продолжает отвечать, обращаясь к базе.
"""

import logging
from collections.abc import Callable
from typing import Any

from depot.domain.access import check_station_access
from depot.domain.enums import UnitCondition
from depot.domain.ids import ModelId, StationId
from depot.domain.models import EquipmentModel, Station, Unit
from depot.repositories.booking import Page
from depot.services.commands import CallContext, CatalogFilters, CreateModelCommand
from depot.services.protocols import Cache, Clock
from depot.services.uow import UnitOfWork

log = logging.getLogger(__name__)

#: список точек выдачи меняется несколько раз в год: держать его в кеше
#: заметно дольше каталога безопасно
STATIONS_TTL = 900
STATIONS_KEY = "catalog:stations:v1"

#: изменяемые поля перечислены явно: цикл по словарю из запроса без белого
#: списка позволяет переписать любой атрибут модели, включая id
UPDATABLE = frozenset({"title", "daily_rate", "deposit", "description"})


class CatalogService:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        clock: Clock,
        cache: Cache,
    ) -> None:
        self._uow_factory = uow_factory
        self._clock = clock
        self._cache = cache

    def search(
        self,
        filters: CatalogFilters,
        ctx: CallContext,
        *,
        sort: str = "title",
        page: int = 1,
        per_page: int = 20,
    ) -> Page[EquipmentModel]:
        # результат поиска не кешируется: сочетаний фильтров слишком много,
        # и почти каждый ключ окажется одноразовым
        with self._uow_factory() as uow:
            return uow.catalog.search(filters, sort=sort, page=page, per_page=per_page)

    def get(self, model_id: ModelId, ctx: CallContext) -> EquipmentModel:
        with self._uow_factory() as uow:
            model = uow.catalog.get(model_id)
            # счётчики считаются здесь, а не в схеме: схема не должна
            # обращаться к базе на этапе сериализации
            model.units_total, model.units_available = self._unit_counters(uow, model_id)
            return model

    def create(self, command: CreateModelCommand, ctx: CallContext) -> EquipmentModel:
        with self._uow_factory() as uow:
            model = EquipmentModel(
                title=command.title,
                category=command.category,
                daily_rate=command.daily_rate,
                deposit=command.deposit,
                description=command.description,
            )
            uow.catalog.add(model)
            log.info(
                "catalog model created",
                extra={"model_id": model.id, "actor_id": ctx.actor.id},
            )
            return model

    def update(
        self, model_id: ModelId, changes: dict[str, Any], ctx: CallContext
    ) -> EquipmentModel:
        with self._uow_factory() as uow:
            model = uow.catalog.get(model_id)
            for field, value in changes.items():
                if field not in UPDATABLE:
                    continue
                setattr(model, field, value)
            model.units_total, model.units_available = self._unit_counters(uow, model_id)
            return model

    def stations(self, ctx: CallContext) -> list[Station]:
        with self._uow_factory() as uow:
            return uow.stations.active()

    def units_of(self, station_id: StationId, ctx: CallContext) -> list[Unit]:
        """Парк конкретной точки.

        Оператор видит только свою точку: проверка выполняется до запроса,
        а не фильтрацией результата — так в журнал не попадёт чужая выборка.
        """
        check_station_access(ctx.actor, station_id)
        with self._uow_factory() as uow:
            return uow.units.for_station(station_id)

    @staticmethod
    def _unit_counters(uow: UnitOfWork, model_id: ModelId) -> tuple[int, int]:
        from sqlalchemy import func, select

        total, available = uow.session.execute(
            select(
                func.count(Unit.id),
                func.count(Unit.id).filter(Unit.condition == UnitCondition.SERVICEABLE),
            ).where(Unit.model_id == model_id)
        ).one()
        return int(total), int(available)
