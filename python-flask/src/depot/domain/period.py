"""Интервал времени.

Границы всегда с часовым поясом: инвариант проверяется в конструкторе,
поэтому дальше по коду о нём можно не думать.
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo


@dataclass(frozen=True, slots=True)
class Period:
    starts_at: datetime
    ends_at: datetime

    def __post_init__(self) -> None:
        if self.starts_at.tzinfo is None or self.ends_at.tzinfo is None:
            raise ValueError("границы периода должны быть с часовым поясом")
        if self.ends_at <= self.starts_at:
            raise ValueError("конец периода должен быть позже начала")

    @property
    def duration(self) -> timedelta:
        return self.ends_at - self.starts_at

    @property
    def hours(self) -> float:
        return self.duration.total_seconds() / 3600

    def overlaps(self, other: "Period", buffer: timedelta = timedelta()) -> bool:
        """Пересечение с буфером.

        Строгие неравенства: интервалы, соприкасающиеся концами, пересечением
        не считаются.
        """
        return (
            self.starts_at < other.ends_at + buffer
            and other.starts_at < self.ends_at + buffer
        )

    def calendar_days(self, timezone: str) -> int:
        """Число суток тарификации по календарным дням в зоне станции.

        Аренда с 23:00 до 01:00 — двое суток: границей служит календарный день,
        а не длительность.
        """
        tz = ZoneInfo(timezone)
        first: date = self.starts_at.astimezone(tz).date()
        last: date = self.ends_at.astimezone(tz).date()
        if self.ends_at.astimezone(tz).time() == time.min and last > first:
            last -= timedelta(days=1)
        return (last - first).days + 1

    def __str__(self) -> str:
        return f"{self.starts_at.isoformat()}..{self.ends_at.isoformat()}"
