"""Сценарии бронирования через HTTP.

Уровень выбран сознательно: проверяются код состояния, форма тела и
заголовки — то, что видит клиент. Правила пересечения периодов и расчёт
цены покрыты тестами домена и здесь не дублируются.
"""

from datetime import UTC, datetime, timedelta

import pytest

from depot.domain.enums import BookingStatus, UnitCondition, UserRole
from tests.factories import make_booking, make_station, make_unit, make_user


@pytest.fixture
def station():  # type: ignore[no-untyped-def]
    return make_station()


@pytest.fixture
def unit(station):  # type: ignore[no-untyped-def]
    return make_unit(station_id=station.id)


@pytest.fixture
def client_user():  # type: ignore[no-untyped-def]
    return make_user(role=UserRole.CLIENT)


def payload(unit_id: int, *, days_ahead: int = 1, days: int = 2) -> dict[str, object]:
    start = datetime.now(UTC) + timedelta(days=days_ahead)
    return {
        "unit_id": unit_id,
        "starts_at": start.isoformat(),
        "ends_at": (start + timedelta(days=days)).isoformat(),
        "note": "съёмка в студии",
    }


class TestCreate:
    def test_creates_and_returns_location(self, client, auth_headers, client_user, unit):  # type: ignore[no-untyped-def]
        response = client.post(
            "/api/v1/bookings", json=payload(unit.id), headers=auth_headers(client_user)
        )
        assert response.status_code == 201
        assert response.headers["Location"].startswith("/api/v1/bookings/")
        body = response.get_json()
        assert body["status"] == BookingStatus.PENDING
        # сумма — строка: число с плавающей точкой в JSON теряет копейки
        assert isinstance(body["total"], str)

    def test_requires_token(self, client, unit):  # type: ignore[no-untyped-def]
        response = client.post("/api/v1/bookings", json=payload(unit.id))
        assert response.status_code == 401
        assert response.headers["WWW-Authenticate"].startswith("Bearer")

    def test_rejects_past_period(self, client, auth_headers, client_user, unit):  # type: ignore[no-untyped-def]
        response = client.post(
            "/api/v1/bookings",
            json=payload(unit.id, days_ahead=-3),
            headers=auth_headers(client_user),
        )
        assert response.status_code == 400
        assert response.get_json()["error"]["code"] == "validation_failed"

    def test_rejects_unknown_field(self, client, auth_headers, client_user, unit):  # type: ignore[no-untyped-def]
        # опечатка в имени поля должна быть ошибкой, а не тишиной
        body = payload(unit.id) | {"comment": "не то поле"}
        response = client.post(
            "/api/v1/bookings", json=body, headers=auth_headers(client_user)
        )
        assert response.status_code == 400
        details = response.get_json()["error"]["details"]
        assert any(d["code"] == "unknown_field" for d in details)

    def test_overlapping_period_conflicts(self, client, auth_headers, client_user, unit):  # type: ignore[no-untyped-def]
        body = payload(unit.id)
        first = client.post("/api/v1/bookings", json=body, headers=auth_headers(client_user))
        assert first.status_code == 201

        second = client.post("/api/v1/bookings", json=body, headers=auth_headers(client_user))
        assert second.status_code == 409
        assert second.get_json()["error"]["code"] == "booking_overlap"

    def test_retired_unit_rejected(self, client, auth_headers, client_user, station):  # type: ignore[no-untyped-def]
        retired = make_unit(station_id=station.id, condition=UnitCondition.RETIRED)
        response = client.post(
            "/api/v1/bookings",
            json=payload(retired.id),
            headers=auth_headers(client_user),
        )
        assert response.status_code == 409


class TestVisibility:
    def test_client_does_not_see_foreign_booking(self, client, auth_headers, unit):  # type: ignore[no-untyped-def]
        owner = make_user(role=UserRole.CLIENT)
        stranger = make_user(role=UserRole.CLIENT)
        booking = make_booking(user_id=owner.id, unit_id=unit.id)

        response = client.get(
            f"/api/v1/bookings/{booking.id}", headers=auth_headers(stranger)
        )
        # 404, а не 403: ответ не подтверждает существование чужой брони
        assert response.status_code == 404

    def test_operator_sees_own_station(self, client, auth_headers, station, unit):  # type: ignore[no-untyped-def]
        operator = make_user(role=UserRole.OPERATOR, station_id=station.id)
        booking = make_booking(unit_id=unit.id)

        response = client.get(
            f"/api/v1/bookings/{booking.id}", headers=auth_headers(operator)
        )
        assert response.status_code == 200


class TestConfirm:
    def test_client_cannot_confirm(self, client, auth_headers, client_user, unit):  # type: ignore[no-untyped-def]
        booking = make_booking(user_id=client_user.id, unit_id=unit.id)
        response = client.post(
            f"/api/v1/bookings/{booking.id}/confirm", headers=auth_headers(client_user)
        )
        assert response.status_code == 403

    def test_operator_confirms(self, client, auth_headers, station, unit):  # type: ignore[no-untyped-def]
        operator = make_user(role=UserRole.OPERATOR, station_id=station.id)
        booking = make_booking(
            unit_id=unit.id,
            hold_expires_at=datetime.now(UTC) + timedelta(minutes=30),
        )
        response = client.post(
            f"/api/v1/bookings/{booking.id}/confirm", headers=auth_headers(operator)
        )
        assert response.status_code == 200
        assert response.get_json()["status"] == BookingStatus.CONFIRMED

    def test_cancelled_booking_is_not_confirmable(self, client, auth_headers, station, unit):  # type: ignore[no-untyped-def]
        operator = make_user(role=UserRole.OPERATOR, station_id=station.id)
        booking = make_booking(unit_id=unit.id, status=BookingStatus.CANCELLED)
        response = client.post(
            f"/api/v1/bookings/{booking.id}/confirm", headers=auth_headers(operator)
        )
        assert response.status_code == 409
        assert response.get_json()["error"]["code"] == "invalid_transition"
