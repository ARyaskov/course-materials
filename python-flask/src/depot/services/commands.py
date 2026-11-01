"""Объекты команд — вход сервисного слоя.

Отличаются от схем API тремя вещами: используют доменные типы (`Period` вместо
двух дат, `UnitId` вместо `int`), неизменяемы и ничего не знают о HTTP.
Поэтому сервис остаётся вызываемым из очереди и из командной строки.
"""

from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from typing import Any, Final

from depot.domain.access import Actor
from depot.domain.enums import EquipmentCategory, UnitCondition
from depot.domain.ids import BookingId, ModelId, RentalId, StationId, UnitId, UserId
from depot.domain.period import Period


class _Unset:
    """Признак отсутствия поля в запросе.

    Отличает «не менять» от «очистить»: `None` для этого недостаточно.
    """

    __slots__ = ()

    def __repr__(self) -> str:
        return "UNSET"

    def __bool__(self) -> bool:
        return False


UNSET: Final = _Unset()


@dataclass(frozen=True, slots=True)
class CallContext:
    """Обстоятельства вызова, отделённые от данных операции.

    Меняются независимо от предметной области: та же операция из CLI получит
    другой источник и не получит ключ идемпотентности.
    """

    actor: Actor
    request_id: str = ""
    source: str = "api"
    idempotency_key: str | None = None
    client_ip: str = ""
    user_agent: str = ""


@dataclass(frozen=True, slots=True)
class CreateBookingCommand:
    user_id: UserId
    unit_id: UnitId
    period: Period
    note: str | None = None
    source: str = "api"
    # кортеж, а не список: объект неизменяем и хешируем
    tags: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True, slots=True)
class UpdateBookingCommand:
    booking_id: BookingId
    note: str | None | _Unset = UNSET
    period: Period | None | _Unset = UNSET


@dataclass(frozen=True, slots=True)
class ConfirmBookingCommand:
    booking_id: BookingId


@dataclass(frozen=True, slots=True)
class CancelBookingCommand:
    booking_id: BookingId
    reason: str | None = None


@dataclass(frozen=True, slots=True)
class IssueRentalCommand:
    booking_id: BookingId


@dataclass(frozen=True, slots=True)
class ReturnRentalCommand:
    rental_id: RentalId
    condition: UnitCondition
    damage_description: str | None = None
    damage_cost: Decimal | None = None


@dataclass(frozen=True, slots=True)
class CreateModelCommand:
    title: str
    category: EquipmentCategory
    daily_rate: Decimal
    deposit: Decimal
    description: str | None = None


@dataclass(frozen=True, slots=True)
class MoveUnitCommand:
    unit_id: UnitId
    target_station_id: StationId


@dataclass(frozen=True, slots=True)
class RegisterUserCommand:
    email: str
    password: str
    full_name: str


@dataclass(frozen=True, slots=True)
class ImportCatalogCommand:
    user_id: UserId
    file_key: str


@dataclass(frozen=True, slots=True)
class CatalogFilters:
    category: EquipmentCategory | None = None
    station_id: StationId | None = None
    min_rate: Decimal | None = None
    max_rate: Decimal | None = None
    query: str | None = None
    available_from: datetime | None = None
    available_to: datetime | None = None


@dataclass(frozen=True, slots=True)
class BookingFilters:
    status: Any = None
    station_id: StationId | None = None
    unit_id: UnitId | None = None
    model_id: ModelId | None = None
    starts_after: datetime | None = None
    starts_before: datetime | None = None
