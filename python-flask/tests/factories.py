"""Фабрики объектов для тестов.

Тест задаёт только то, что проверяет; остальное фабрика подставляет сама.
Иначе половина каждого теста — заполнение полей, к делу не относящихся,
и добавление обязательной колонки правит сотню файлов вместо одного.
"""

import itertools
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from werkzeug.security import generate_password_hash

from depot.domain.enums import (
    BookingStatus,
    EquipmentCategory,
    UnitCondition,
    UserRole,
)
from depot.domain.models import Booking, EquipmentModel, Station, Unit, User
from depot.extensions import db

#: счётчик для уникальных значений: генератор случайности иногда
#: повторяется и даёт «плавающие» падения на уникальных ограничениях
_counter = itertools.count(1)


def make_user(**overrides: Any) -> User:
    number = next(_counter)
    fields: dict[str, Any] = {
        "email": f"user{number}@example.com",
        "password_hash": generate_password_hash("correct-horse-battery"),
        "full_name": f"Пользователь {number}",
        "role": UserRole.CLIENT,
        "password_changed_at": datetime.now(UTC),
    }
    fields.update(overrides)
    user = User(**fields)
    db.session.add(user)
    db.session.flush()
    return user


def make_station(**overrides: Any) -> Station:
    number = next(_counter)
    fields: dict[str, Any] = {
        "title": f"Точка {number}",
        "address": f"ул. Примерная, {number}",
        "timezone": "Europe/Moscow",
    }
    fields.update(overrides)
    station = Station(**fields)
    db.session.add(station)
    db.session.flush()
    return station


def make_model(**overrides: Any) -> EquipmentModel:
    number = next(_counter)
    fields: dict[str, Any] = {
        "title": f"Камера {number}",
        "category": EquipmentCategory.CAMERA,
        "daily_rate": Decimal("3500.00"),
        "deposit": Decimal("50000.00"),
    }
    fields.update(overrides)
    model = EquipmentModel(**fields)
    db.session.add(model)
    db.session.flush()
    return model


def make_unit(**overrides: Any) -> Unit:
    number = next(_counter)
    fields: dict[str, Any] = {
        "serial": f"SN-{number:06d}",
        "condition": UnitCondition.GOOD,
    }
    fields.update(overrides)
    # связанные объекты создаются только если не переданы: иначе тест
    # получит вторую точку выдачи там, где ожидал одну
    fields.setdefault("model_id", make_model().id)
    fields.setdefault("station_id", make_station().id)
    unit = Unit(**fields)
    db.session.add(unit)
    db.session.flush()
    return unit


def make_booking(**overrides: Any) -> Booking:
    starts_at = overrides.pop("starts_at", datetime.now(UTC) + timedelta(days=1))
    ends_at = overrides.pop("ends_at", starts_at + timedelta(days=2))

    fields: dict[str, Any] = {
        "status": BookingStatus.PENDING,
        "starts_at": starts_at,
        "ends_at": ends_at,
        "total": Decimal("7000.00"),
        "currency": "RUB",
    }
    fields.update(overrides)
    fields.setdefault("user_id", make_user().id)
    fields.setdefault("unit_id", make_unit().id)
    booking = Booking(**fields)
    db.session.add(booking)
    db.session.flush()
    return booking
