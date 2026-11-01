"""Модели SQLAlchemy.

Компромисс проекта: модели лежат в доменном слое, но правила и расчёты —
в модулях без зависимости от SQLAlchemy, поэтому тестируются без базы.
Обоснование и условия пересмотра — в docs/decisions.md.

Все связи объявлены с `lazy="raise"`: обращение к незагруженной связи даёт
ошибку сразу, а не тихий дополнительный запрос.
"""

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    UniqueConstraint,
    desc,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from depot.domain.enums import (
    BookingStatus,
    EquipmentCategory,
    ImportStatus,
    InvoiceLineKind,
    InvoiceStatus,
    UnitCondition,
    UserRole,
)
from depot.extensions import db


class TimestampMixin:
    """Метки времени задаёт база: значение едино для всех источников записи."""

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class Station(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "stations"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    address: Mapped[str] = mapped_column(String(500), nullable=False)
    # имя зоны, а не смещение: смещение меняется при переводе часов
    timezone: Mapped[str] = mapped_column(
        String(64), nullable=False, server_default="Europe/Moscow"
    )
    is_active: Mapped[bool] = mapped_column(nullable=False, server_default=text("true"))

    units: Mapped[list["Unit"]] = relationship(back_populates="station", lazy="raise")


class EquipmentModel(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "equipment_models"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[EquipmentCategory] = mapped_column(
        String(32), nullable=False, index=True
    )
    daily_rate: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    deposit: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="RUB")
    description: Mapped[str | None] = mapped_column(String(2000))

    __table_args__ = (
        CheckConstraint("daily_rate > 0", name="daily_rate_positive"),
        CheckConstraint("deposit >= 0", name="deposit_non_negative"),
        Index("ix_equipment_models_category_rate", "category", "daily_rate"),
        # функциональный индекс: поиск идёт по началу названия без учёта регистра
        Index("ix_equipment_models_title_lower", func.lower(title)),
    )


class Unit(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "units"

    id: Mapped[int] = mapped_column(primary_key=True)
    serial: Mapped[str] = mapped_column(String(64), nullable=False)
    model_id: Mapped[int] = mapped_column(
        ForeignKey("equipment_models.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    station_id: Mapped[int] = mapped_column(
        ForeignKey("stations.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    condition: Mapped[UnitCondition] = mapped_column(
        String(20), nullable=False, server_default=UnitCondition.GOOD.value
    )

    model: Mapped[EquipmentModel] = relationship(lazy="raise")
    station: Mapped[Station] = relationship(back_populates="units", lazy="raise")

    __table_args__ = (
        UniqueConstraint("serial", name="uq_units_serial"),
        Index("ix_units_station_condition", "station_id", "condition"),
    )


class User(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str] = mapped_column(String(200), nullable=False)
    role: Mapped[UserRole] = mapped_column(
        String(20), nullable=False, server_default=UserRole.CLIENT.value
    )
    station_id: Mapped[int | None] = mapped_column(
        ForeignKey("stations.id", ondelete="RESTRICT")
    )
    is_active: Mapped[bool] = mapped_column(nullable=False, server_default=text("true"))
    # момент смены пароля — механизм массового отзыва токенов
    password_changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        # обычная уникальность пропустила бы адрес, отличающийся регистром
        Index("uq_users_email_lower", func.lower(email), unique=True),
        CheckConstraint(
            "(role = 'operator' and station_id is not null) or "
            "(role <> 'operator' and station_id is null)",
            name="operator_has_station",
        ),
    )


class Booking(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "bookings"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    unit_id: Mapped[int] = mapped_column(
        ForeignKey("units.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[BookingStatus] = mapped_column(String(20), nullable=False, index=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    hold_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="RUB")
    note: Mapped[str | None] = mapped_column(String(500))
    cancel_reason: Mapped[str | None] = mapped_column(String(500))
    payment_hold_id: Mapped[str | None] = mapped_column(String(64))
    notification_pending: Mapped[bool] = mapped_column(
        nullable=False, server_default=text("false")
    )
    # оптимистичная блокировка: параллельное редактирование не затрёт чужие правки
    version: Mapped[int] = mapped_column(nullable=False, server_default=text("1"))

    unit: Mapped[Unit] = relationship(lazy="raise")
    rental: Mapped["Rental | None"] = relationship(
        back_populates="booking", lazy="raise", uselist=False
    )

    __mapper_args__ = {"version_id_col": version}

    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="period_valid"),
        CheckConstraint("total >= 0", name="total_non_negative"),
        CheckConstraint(
            "status in ('pending','confirmed','cancelled','completed','expired')",
            name="status_valid",
        ),
        Index("ix_bookings_user_created", "user_id", desc("created_at")),
        # частичный индекс: активных броней тысячи, всех — миллионы
        Index(
            "ix_bookings_active_period",
            "unit_id",
            "starts_at",
            postgresql_where=text("status in ('pending','confirmed')"),
        ),
        # ограничение исключения bookings_no_overlap добавляется миграцией 0005:
        # Alembic его не генерирует, а проверка в коде не спасает от гонки
    )

    @property
    def public_id(self) -> str:
        return str(self.id)

    @property
    def station_id(self) -> int:
        return self.unit.station_id


class Rental(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "rentals"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    booking_id: Mapped[UUID] = mapped_column(
        ForeignKey("bookings.id", ondelete="RESTRICT"), nullable=False
    )
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    returned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    issued_by: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )

    booking: Mapped[Booking] = relationship(back_populates="rental", lazy="raise")
    damage_reports: Mapped[list["DamageReport"]] = relationship(
        back_populates="rental", cascade="all, delete-orphan", lazy="raise"
    )

    __table_args__ = (
        UniqueConstraint("booking_id", name="uq_rentals_booking"),
        CheckConstraint(
            "returned_at is null or returned_at >= issued_at", name="return_after_issue"
        ),
        # частичный индекс под фоновую задачу начисления штрафов
        Index("ix_rentals_overdue", "due_at", postgresql_where=text("returned_at is null")),
    )

    # свойства ниже реализуют протоколы из depot.domain.access: домен
    # проверяет доступ, не зная строения таблиц

    @property
    def public_id(self) -> str:
        return str(self.id)

    @property
    def owner_id(self) -> int:
        return self.booking.user_id

    @property
    def station_id(self) -> int:
        return self.booking.unit.station_id

    @property
    def is_overdue(self) -> bool:
        """Просрочка на текущий момент.

        Закрытая аренда не считается просроченной задним числом: факт
        задержки фиксируется строкой счёта, а не этим признаком.
        """
        if self.returned_at is not None:
            return False
        return self.due_at < datetime.now(self.due_at.tzinfo)


class DamageReport(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "damage_reports"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    rental_id: Mapped[UUID] = mapped_column(
        ForeignKey("rentals.id", ondelete="CASCADE"), nullable=False, index=True
    )
    description: Mapped[str] = mapped_column(String(2000), nullable=False)
    severity: Mapped[str] = mapped_column(String(20), nullable=False)
    estimated_cost: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    rental: Mapped[Rental] = relationship(back_populates="damage_reports", lazy="raise")
    photos: Mapped[list["DamagePhoto"]] = relationship(
        back_populates="report", cascade="all, delete-orphan", lazy="raise"
    )


class DamagePhoto(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "damage_photos"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    report_id: Mapped[UUID] = mapped_column(
        ForeignKey("damage_reports.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # имя генерируется; оригинальное хранится как метаданные
    storage_key: Mapped[str] = mapped_column(String(500), nullable=False, unique=True)
    original_name: Mapped[str] = mapped_column(String(255), nullable=False)
    media_type: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(nullable=False)
    checksum: Mapped[str] = mapped_column(String(64), nullable=False)

    report: Mapped[DamageReport] = relationship(back_populates="photos", lazy="raise")


class Invoice(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "invoices"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    booking_id: Mapped[UUID] = mapped_column(
        ForeignKey("bookings.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    status: Mapped[InvoiceStatus] = mapped_column(
        String(20), nullable=False, server_default=InvoiceStatus.DRAFT.value
    )
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="RUB")
    issued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    lines: Mapped[list["InvoiceLine"]] = relationship(
        back_populates="invoice", cascade="all, delete-orphan", lazy="raise"
    )

    __table_args__ = (CheckConstraint("total >= 0", name="invoice_total_non_negative"),)


class InvoiceLine(db.Model):  # type: ignore[name-defined]
    __tablename__ = "invoice_lines"

    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_id: Mapped[UUID] = mapped_column(
        ForeignKey("invoices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[InvoiceLineKind] = mapped_column(String(20), nullable=False)
    day: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    description: Mapped[str] = mapped_column(String(500), nullable=False)

    invoice: Mapped[Invoice] = relationship(back_populates="lines", lazy="raise")

    __table_args__ = (
        # делает двойное начисление за один день невозможным даже при гонке
        UniqueConstraint("invoice_id", "kind", "day", name="uq_invoice_lines_kind_day"),
    )


class RefreshSession(db.Model):  # type: ignore[name-defined]
    __tablename__ = "refresh_sessions"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # хранится хеш: утечка таблицы не даёт готовых токенов
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    user_agent: Mapped[str | None] = mapped_column(String(255))
    ip: Mapped[str | None] = mapped_column(String(45))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        Index(
            "ix_refresh_sessions_active",
            "user_id",
            postgresql_where=text("revoked_at is null"),
        ),
    )


class IdempotencyRecord(db.Model):  # type: ignore[name-defined]
    __tablename__ = "idempotency_records"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(nullable=False)
    # отпечаток тела: тот же ключ с другими данными — это не повтор, а конфликт
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    response_body: Mapped[dict] = mapped_column(JSONB, nullable=False)
    status_code: Mapped[int] = mapped_column(nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )


class ImportJob(TimestampMixin, db.Model):  # type: ignore[name-defined]
    __tablename__ = "import_jobs"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    status: Mapped[ImportStatus] = mapped_column(
        String(20), nullable=False, server_default=ImportStatus.QUEUED.value
    )
    file_key: Mapped[str] = mapped_column(String(500), nullable=False)
    total_rows: Mapped[int] = mapped_column(nullable=False, server_default=text("0"))
    # прогресс в базе делает задачу возобновляемой после прерывания
    processed_rows: Mapped[int] = mapped_column(nullable=False, server_default=text("0"))
    succeeded: Mapped[int] = mapped_column(nullable=False, server_default=text("0"))
    failed: Mapped[int] = mapped_column(nullable=False, server_default=text("0"))
    errors: Mapped[list] = mapped_column(JSONB, nullable=False, server_default=text("'[]'"))
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditRecord(db.Model):  # type: ignore[name-defined]
    __tablename__ = "audit_records"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    actor_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    action: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(String(32), nullable=False)
    target_id: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
