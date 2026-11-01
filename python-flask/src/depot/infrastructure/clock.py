"""Источники времени."""

from datetime import UTC, datetime, timedelta


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)


class FixedClock:
    """Часы для тестов.

    Позволяют проверить истечение удержания без ожидания и без подмены
    системных функций: любое ожидание в тесте — дефект.
    """

    def __init__(self, moment: datetime) -> None:
        self.moment = moment

    def now(self) -> datetime:
        return self.moment

    def advance(self, delta: timedelta) -> None:
        self.moment += delta
