"""Работа со временем.

Домен принимает момент параметром и никогда не спрашивает его сам:
функция, которая внутри вызывает `now()`, непроверяема — её поведение
зависит от того, в какую секунду запущен тест.

Подменяемый источник времени объявлен протоколом `Clock`
в `services/protocols.py`, реализации — в `infrastructure/clock.py`.
Здесь живут только чистые преобразования.
"""

from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

#: минимальный шаг, с которым имеет смысл сравнивать метки времени:
#: PostgreSQL хранит timestamptz с точностью до микросекунды
RESOLUTION = timedelta(microseconds=1)


def ensure_aware(value: datetime, assume: str = "UTC") -> datetime:
    """Привести значение к времени со смещением.

    Наивное значение — источник ошибок, которые проявляются дважды в год
    и на границе суток. Здесь оно не отбрасывается, а трактуется явно:
    вызывающий сам указывает, в каком поясе оно записано.
    """
    if value.tzinfo is not None:
        return value
    return value.replace(tzinfo=ZoneInfo(assume))


def to_utc(value: datetime) -> datetime:
    """Перевести в UTC для хранения.

    В базе всё лежит в UTC. Часовой пояс — свойство представления,
    а не свойство момента времени.
    """
    return ensure_aware(value).astimezone(UTC)


def in_zone(value: datetime, timezone: str) -> datetime:
    """Показать момент в часовом поясе точки выдачи."""
    return ensure_aware(value).astimezone(ZoneInfo(timezone))


def calendar_days(start: datetime, end: datetime, timezone: str) -> int:
    """Число календарных суток между моментами в заданном поясе.

    Именно календарных, а не «часов, делённых на 24»: аренда с 23:00
    до 01:00 занимает двое суток по тарифу. Сутки считаются в поясе
    точки выдачи — сервер и клиент могут находиться где угодно.
    """
    local_start = in_zone(start, timezone).date()
    local_end = in_zone(end, timezone).date()
    # хотя бы одни сутки: аренда на двадцать минут не бесплатна
    return max((local_end - local_start).days, 0) + 1


def isoformat(value: datetime) -> str:
    """Строка для ответа API — всегда со смещением."""
    return ensure_aware(value).isoformat()


def parse_iso(raw: str) -> datetime:
    """Разбор строки с обязательным смещением.

    `fromisoformat` принимает и значение без смещения; здесь это ошибка,
    а не повод молча подставить пояс сервера.
    """
    value = datetime.fromisoformat(raw)
    if value.tzinfo is None:
        raise ValueError("требуется смещение часового пояса")
    return value
