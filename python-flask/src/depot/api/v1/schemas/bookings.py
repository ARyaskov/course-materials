"""Схемы бронирования."""

from datetime import UTC, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from pydantic import Field, model_validator

from depot.api.v1.schemas.base import InputSchema, OutputSchema
from depot.api.v1.schemas.types import AwareDatetime, Page, PerPage
from depot.domain.enums import BookingStatus
from depot.domain.rules import MAX_BOOKING_DURATION

#: запас на расхождение часов клиента и сервера: без него бронь «через минуту»
#: отклоняется у части пользователей
CLOCK_SKEW = timedelta(minutes=5)


class BookingCreate(InputSchema):
    unit_id: int = Field(ge=1)
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    note: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def check_period(self) -> "BookingCreate":
        """Проверки, которым нужны оба поля сразу.

        Режим after даёт уже приведённые значения: сравнивать datetime
        со строкой не придётся.
        """
        if self.ends_at <= self.starts_at:
            raise ValueError("окончание должно быть позже начала")
        if self.ends_at - self.starts_at > MAX_BOOKING_DURATION:
            raise ValueError(
                f"максимальный срок аренды — {MAX_BOOKING_DURATION.days} дней"
            )
        if self.starts_at < datetime.now(UTC) - CLOCK_SKEW:
            raise ValueError("нельзя забронировать прошедшее время")
        return self


class BookingUpdate(InputSchema):
    starts_at: AwareDatetime | None = None
    ends_at: AwareDatetime | None = None
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def check_period(self) -> "BookingUpdate":
        # период меняется целиком: одна граница без другой не позволяет
        # проверить длительность и пересечения
        if bool(self.starts_at) != bool(self.ends_at):
            raise ValueError("starts_at и ends_at передаются вместе")
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("окончание должно быть позже начала")
        return self


class BookingQuery(InputSchema):
    status: BookingStatus | None = None
    station_id: int | None = Field(default=None, ge=1)
    unit_id: int | None = Field(default=None, ge=1)
    from_date: AwareDatetime | None = None
    to_date: AwareDatetime | None = None
    sort: str = Field(default="-created_at", max_length=32)
    page: Page = 1
    per_page: PerPage = 20


class CancelRequest(InputSchema):
    reason: str = Field(default="", max_length=300)


class BookingOut(OutputSchema):
    id: UUID
    status: BookingStatus
    unit_id: int
    starts_at: datetime
    ends_at: datetime
    total: Decimal
    currency: str
    created_at: datetime


class BookingDetailOut(BookingOut):
    note: str | None = None
    hold_expires_at: datetime | None = None
    cancel_reason: str | None = None
