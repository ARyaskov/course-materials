"""Перечисления предметной области.

Значения записаны явно: они хранятся в базе и уходят в API, поэтому не должны
меняться вместе с именами членов.
"""

from enum import StrEnum


class UserRole(StrEnum):
    CLIENT = "client"
    OPERATOR = "operator"
    ADMIN = "admin"


class EquipmentCategory(StrEnum):
    CAMERA = "camera"
    LENS = "lens"
    LIGHT = "light"
    AUDIO = "audio"


class UnitCondition(StrEnum):
    NEW = "new"
    GOOD = "good"
    WORN = "worn"
    NEEDS_REPAIR = "needs_repair"
    RETIRED = "retired"


class BookingStatus(StrEnum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    COMPLETED = "completed"
    EXPIRED = "expired"

    @property
    def is_final(self) -> bool:
        return self in _FINAL_STATUSES


class InvoiceStatus(StrEnum):
    DRAFT = "draft"
    ISSUED = "issued"
    PAID = "paid"
    VOID = "void"


class InvoiceLineKind(StrEnum):
    RENTAL = "rental"
    LATE_FEE = "late_fee"
    DAMAGE = "damage"
    DEPOSIT_HOLD = "deposit_hold"


class ImportStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"


class BookingAction(StrEnum):
    VIEW = "view"
    UPDATE = "update"
    CANCEL = "cancel"
    CONFIRM = "confirm"


class RentalAction(StrEnum):
    VIEW = "view"
    ISSUE = "issue"
    RETURN = "return"


class Permission(StrEnum):
    CATALOG_READ = "catalog:read"
    CATALOG_WRITE = "catalog:write"
    BOOKING_CREATE = "booking:create"
    BOOKING_CONFIRM = "booking:confirm"
    BOOKING_CANCEL_ANY = "booking:cancel_any"
    RENTAL_ISSUE = "rental:issue"
    RENTAL_RETURN = "rental:return"
    INVOICE_READ_ANY = "invoice:read_any"
    INVOICE_VOID = "invoice:void"
    CATALOG_IMPORT = "catalog:import"
    STATION_MANAGE = "station:manage"
    USER_MANAGE = "user:manage"


_FINAL_STATUSES = frozenset(
    {BookingStatus.CANCELLED, BookingStatus.COMPLETED, BookingStatus.EXPIRED}
)

ACTIVE_BOOKING_STATUSES: tuple[BookingStatus, ...] = (
    BookingStatus.PENDING,
    BookingStatus.CONFIRMED,
)

BOOKING_STATUS_LABELS: dict[BookingStatus, str] = {
    BookingStatus.PENDING: "Ожидает подтверждения",
    BookingStatus.CONFIRMED: "Подтверждена",
    BookingStatus.CANCELLED: "Отменена",
    BookingStatus.COMPLETED: "Завершена",
    BookingStatus.EXPIRED: "Просрочена",
}
