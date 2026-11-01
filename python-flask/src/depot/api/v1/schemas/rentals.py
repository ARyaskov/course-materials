"""Схемы выдачи, возврата и счетов."""

from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import Field

from depot.api.v1.schemas.base import InputSchema, OutputSchema
from depot.api.v1.schemas.types import Page, PerPage
from depot.domain.enums import ImportStatus, InvoiceLineKind, InvoiceStatus, UnitCondition


class IssueRequest(InputSchema):
    booking_id: UUID
    checklist_ok: bool = Field(
        description="Осмотр перед выдачей проведён",
    )


class ReturnRequest(InputSchema):
    """Приём оборудования.

    Состояние экземпляра обязательно: без него приёмка сводится к нажатию
    кнопки, и повреждения всплывают на следующем клиенте.
    """

    condition: UnitCondition
    damage_description: str | None = Field(default=None, min_length=5, max_length=2000)
    # оценку даёт приёмщик, но верхняя граница проверяется в сервисе
    # по залогу модели
    damage_cost: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    photo_keys: list[str] = Field(default_factory=list, max_length=10)


class RentalQuery(InputSchema):
    overdue_only: bool = False
    page: Page = 1
    per_page: PerPage = 20


class RentalOut(OutputSchema):
    id: UUID
    booking_id: UUID
    issued_at: datetime
    due_at: datetime
    returned_at: datetime | None = None
    is_overdue: bool


class InvoiceLineOut(OutputSchema):
    kind: InvoiceLineKind
    description: str
    amount: Decimal


class InvoiceOut(OutputSchema):
    id: UUID
    booking_id: UUID
    status: InvoiceStatus
    total: Decimal
    currency: str
    issued_at: datetime | None = None
    paid_at: datetime | None = None
    lines: list[InvoiceLineOut] = Field(default_factory=list)


class ImportRequest(InputSchema):
    """Запуск импорта каталога.

    Файл уже загружен отдельным запросом: держать многомегабайтное тело
    в памяти обработчика ради постановки задачи не нужно.
    """

    file_key: str = Field(min_length=8, max_length=500)


class ImportJobOut(OutputSchema):
    id: UUID
    status: ImportStatus
    total_rows: int
    processed_rows: int
    succeeded: int
    failed: int
    started_at: datetime | None = None
    finished_at: datetime | None = None
    errors: list = Field(default_factory=list)
