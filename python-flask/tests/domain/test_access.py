"""Правила доступа.

Проверяется не только «кому можно», но и какая ошибка возвращается:
чужой объект даёт 404, а не 403. Это часть контракта — 403 подтверждает
существование объекта, а значит, отвечает на вопрос, которого не задавали.
"""

from dataclasses import dataclass

import pytest

from depot.domain.access import Actor, check_booking_access, check_station_access
from depot.domain.enums import BookingAction, Permission, UserRole
from depot.domain.errors import NotFound, PermissionDenied
from depot.domain.ids import UserId
from depot.domain.permissions import has_permission, permissions_of


@dataclass(frozen=True)
class FakeBooking:
    """Подстановка вместо модели.

    Правилам доступа нужны три свойства, а не таблица: тест не поднимает
    базу и не зависит от схемы.
    """

    user_id: int
    station_id: int
    public_id: str = "b-1"


CLIENT = Actor(id=UserId(1), role=UserRole.CLIENT)
OTHER_CLIENT = Actor(id=UserId(2), role=UserRole.CLIENT)
OPERATOR = Actor(id=UserId(3), role=UserRole.OPERATOR, station_id=10)
FOREIGN_OPERATOR = Actor(id=UserId(4), role=UserRole.OPERATOR, station_id=20)
ADMIN = Actor(id=UserId(5), role=UserRole.ADMIN)

BOOKING = FakeBooking(user_id=1, station_id=10)


class TestBookingAccess:
    def test_owner_sees_own(self) -> None:
        check_booking_access(CLIENT, BOOKING, BookingAction.VIEW)

    def test_foreign_booking_is_not_found(self) -> None:
        # именно NotFound: PermissionDenied сообщил бы, что бронь существует
        with pytest.raises(NotFound):
            check_booking_access(OTHER_CLIENT, BOOKING, BookingAction.VIEW)

    def test_owner_cannot_confirm(self) -> None:
        # владение объектом не даёт права на все операции над ним
        with pytest.raises(PermissionDenied):
            check_booking_access(CLIENT, BOOKING, BookingAction.CONFIRM)

    def test_operator_of_station_confirms(self) -> None:
        check_booking_access(OPERATOR, BOOKING, BookingAction.CONFIRM)

    def test_operator_of_other_station_gets_not_found(self) -> None:
        with pytest.raises(NotFound):
            check_booking_access(FOREIGN_OPERATOR, BOOKING, BookingAction.VIEW)

    def test_admin_passes_any_action(self) -> None:
        for action in BookingAction:
            check_booking_access(ADMIN, BOOKING, action)


class TestStationAccess:
    def test_operator_limited_to_own_station(self) -> None:
        check_station_access(OPERATOR, 10)
        with pytest.raises(PermissionDenied):
            check_station_access(OPERATOR, 20)

    def test_client_has_no_station(self) -> None:
        with pytest.raises(PermissionDenied):
            check_station_access(CLIENT, 10)


class TestPermissions:
    def test_client_cannot_confirm(self) -> None:
        assert not has_permission(CLIENT, Permission.BOOKING_CONFIRM)

    def test_admin_has_everything(self) -> None:
        assert all(has_permission(ADMIN, p) for p in Permission)

    def test_permissions_are_sorted(self) -> None:
        # порядок предсказуем: ответ API не должен меняться от запуска
        # к запуску из-за порядка обхода множества
        values = permissions_of(UserRole.OPERATOR)
        assert values == sorted(values)
