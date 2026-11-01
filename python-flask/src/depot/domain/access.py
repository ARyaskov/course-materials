"""Правила доступа к объектам.

Чистые функции: принимают актора и объект, ничего не загружают и не меняют.
Чужой объект даёт `NotFound`, а не `PermissionDenied`: ответ не должен
подтверждать существование объекта.
"""

from dataclasses import dataclass
from typing import Protocol

from depot.domain.enums import BookingAction, RentalAction, UserRole
from depot.domain.errors import NotFound, PermissionDenied
from depot.domain.ids import UserId

CLIENT_BOOKING_ACTIONS = frozenset(
    {BookingAction.VIEW, BookingAction.UPDATE, BookingAction.CANCEL}
)
OPERATOR_BOOKING_ACTIONS = frozenset(
    {BookingAction.VIEW, BookingAction.CONFIRM, BookingAction.CANCEL}
)
OPERATOR_RENTAL_ACTIONS = frozenset(
    {RentalAction.VIEW, RentalAction.ISSUE, RentalAction.RETURN}
)


@dataclass(frozen=True, slots=True)
class Actor:
    """Кто выполняет операцию.

    Собирается из данных токена, поэтому не требует обращения к базе.
    """

    id: UserId
    role: UserRole
    station_id: int | None = None
    token_id: str = ""

    @property
    def is_admin(self) -> bool:
        return self.role is UserRole.ADMIN


class HasStation(Protocol):
    @property
    def station_id(self) -> int: ...


class OwnedBooking(Protocol):
    @property
    def user_id(self) -> int: ...

    @property
    def station_id(self) -> int: ...

    @property
    def public_id(self) -> str: ...


def check_booking_access(
    actor: Actor, booking: OwnedBooking, action: BookingAction
) -> None:
    """Доступ к конкретной брони.

    Владение объектом не даёт права на все операции над ним: клиент может
    отменить свою бронь, но подтверждает её оператор при выдаче.
    """
    if actor.is_admin:
        return

    if actor.role is UserRole.OPERATOR:
        if booking.station_id != actor.station_id:
            raise NotFound(f"бронь {booking.public_id} не найдена")
        if action in OPERATOR_BOOKING_ACTIONS:
            return
        raise PermissionDenied("операция недоступна оператору")

    if actor.role is UserRole.CLIENT:
        if booking.user_id != actor.id:
            raise NotFound(f"бронь {booking.public_id} не найдена")
        if action in CLIENT_BOOKING_ACTIONS:
            return
        raise PermissionDenied("операция недоступна клиенту")

    raise PermissionDenied("доступ запрещён")


class OwnedRental(Protocol):
    @property
    def public_id(self) -> str: ...

    @property
    def owner_id(self) -> int: ...

    @property
    def station_id(self) -> int: ...


def check_rental_access(
    actor: Actor, rental: OwnedRental, action: RentalAction
) -> None:
    """Доступ к аренде.

    Клиент видит собственную аренду, но не выдаёт и не принимает её:
    приёмка — обязанность сотрудника точки, и совмещать эти роли значит
    разрешить закрыть аренду без осмотра оборудования.
    """
    if actor.is_admin:
        return

    if actor.role is UserRole.OPERATOR:
        if rental.station_id != actor.station_id:
            raise NotFound(f"аренда {rental.public_id} не найдена")
        if action in OPERATOR_RENTAL_ACTIONS:
            return
        raise PermissionDenied("операция недоступна оператору")

    if actor.role is UserRole.CLIENT:
        if rental.owner_id != actor.id:
            raise NotFound(f"аренда {rental.public_id} не найдена")
        if action is RentalAction.VIEW:
            return
        raise PermissionDenied("операция недоступна клиенту")

    raise PermissionDenied("доступ запрещён")


def check_station_access(actor: Actor, station_id: int) -> None:
    """Доступ к станции.

    Нужен отдельно от доступа к объекту: операции, меняющие принадлежность,
    проверяют и объект в старом состоянии, и целевого владельца — иначе
    оператор мог бы перенести к себе чужое оборудование.
    """
    if actor.is_admin:
        return
    if actor.role is UserRole.OPERATOR and actor.station_id == station_id:
        return
    raise PermissionDenied("станция недоступна")
