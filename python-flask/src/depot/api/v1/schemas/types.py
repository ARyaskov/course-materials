"""Повторно используемые типы полей.

Ограничения объявляются один раз и переиспользуются: иначе одно и то же
поле в трёх схемах получает три разных предела длины.
"""

import re
from datetime import UTC, datetime
from decimal import Decimal
from typing import Annotated

from pydantic import AfterValidator, Field, StringConstraints

Name = Annotated[str, StringConstraints(min_length=2, max_length=120)]
Email = Annotated[str, StringConstraints(min_length=5, max_length=254, to_lower=True)]
Slug = Annotated[str, StringConstraints(pattern=r"^[a-z0-9][a-z0-9-]{1,62}$")]

#: пароль не обрезается по пробелам и не приводится к нижнему регистру:
#: и то и другое молча меняет введённое пользователем значение
Password = Annotated[str, Field(min_length=10, max_length=128)]

#: денежная сумма приходит строкой: число с плавающей точкой в JSON
#: уже потеряло копейки к моменту разбора
Amount = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]

#: верхняя граница страницы обязательна: без неё per_page=100000 превращает
#: список в выгрузку всей таблицы одним запросом
Page = Annotated[int, Field(default=1, ge=1, le=10_000)]
PerPage = Annotated[int, Field(default=20, ge=1, le=100)]


def _require_aware(value: datetime) -> datetime:
    """Отклонение времени без зоны.

    Наивное значение молча трактуется как локальное и даёт расхождение
    в часы — на границе суток это меняет тариф.
    """
    if value.tzinfo is None:
        raise ValueError(
            "требуется смещение часового пояса, например 2026-03-01T10:00:00+03:00"
        )
    return value.astimezone(UTC)


AwareDatetime = Annotated[datetime, AfterValidator(_require_aware)]

_PHONE = re.compile(r"^\+[1-9]\d{7,14}$")


def _check_phone(value: str) -> str:
    normalized = re.sub(r"[\s()-]", "", value)
    if not _PHONE.fullmatch(normalized):
        raise ValueError("телефон в формате +79991234567")
    return normalized


Phone = Annotated[str, AfterValidator(_check_phone)]
