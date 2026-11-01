"""Сериализация ответов.

Настраивается один раз в фабрике и действует на все обработчики.
"""

from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from uuid import UUID

from flask.json.provider import DefaultJSONProvider


def json_default(value: object) -> object:
    """Преобразование типов, которых нет в JSON."""
    if isinstance(value, Decimal):
        # строка, а не float: двоичное представление теряет копейки
        return str(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, (set, frozenset)):
        # множество не упорядочено: наружу уходит отсортированный список
        return sorted(value)
    if isinstance(value, bytes):
        raise TypeError("двоичные данные не сериализуются в JSON")
    # ветка обязательна: без неё модель SQLAlchemy уедет клиенту
    # в виде <Booking object at 0x7f...>
    raise TypeError(f"не сериализуется: {type(value).__name__}")


class DepotJSONProvider(DefaultJSONProvider):
    # кириллица не экранируется: ответ вчетверо компактнее и читаем в логах
    ensure_ascii = False
    # порядок полей — тот, в котором их собрала схема
    sort_keys = False

    @staticmethod
    def default(value: object) -> object:
        return json_default(value)
