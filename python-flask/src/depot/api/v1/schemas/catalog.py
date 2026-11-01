"""Схемы каталога оборудования."""

from datetime import datetime
from decimal import Decimal

from pydantic import Field, field_validator, model_validator

from depot.api.v1.schemas.base import InputSchema, OutputSchema
from depot.api.v1.schemas.types import Amount, AwareDatetime, Name, Page, PerPage
from depot.domain.enums import EquipmentCategory, UnitCondition


class CatalogQuery(InputSchema):
    """Параметры строки запроса.

    Разбираются той же схемой, что и тело: правила проверки не должны
    зависеть от того, каким способом данные приехали. Без схемы per_page
    приезжает строкой "20", а available=false — непустой строкой, то есть
    истинным значением.
    """

    category: EquipmentCategory | None = None
    station_id: int | None = Field(default=None, ge=1)
    q: str | None = Field(default=None, min_length=2, max_length=80)
    min_rate: Amount | None = None
    max_rate: Amount | None = None
    available_from: AwareDatetime | None = None
    available_to: AwareDatetime | None = None
    sort: str = Field(default="title", max_length=32)
    page: Page = 1
    per_page: PerPage = 20

    @field_validator("q")
    @classmethod
    def escape_wildcards(cls, value: str | None) -> str | None:
        """Экранирование символов LIKE.

        Иначе запрос из одного процента возвращает весь каталог и превращает
        поиск в полное сканирование таблицы.
        """
        if value is None:
            return None
        return value.replace("%", r"\%").replace("_", r"\_")

    @model_validator(mode="after")
    def check_range(self) -> "CatalogQuery":
        if self.min_rate and self.max_rate and self.min_rate > self.max_rate:
            raise ValueError("min_rate не может быть больше max_rate")
        if self.available_from and self.available_to:
            if self.available_to <= self.available_from:
                raise ValueError("available_to должен быть позже available_from")
        return self


class ModelCreate(InputSchema):
    title: Name
    category: EquipmentCategory
    daily_rate: Amount
    deposit: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    description: str | None = Field(default=None, max_length=2000)


class ModelUpdate(InputSchema):
    """Частичное обновление.

    Все поля необязательны, но exclude_unset в обработчике отличает
    «не передано» от «передано null».
    """

    title: Name | None = None
    daily_rate: Amount | None = None
    deposit: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    description: str | None = Field(default=None, max_length=2000)


class UnitOut(OutputSchema):
    id: int
    serial: str
    condition: UnitCondition
    station_id: int
    model_id: int


class ModelOut(OutputSchema):
    id: int
    title: str
    category: EquipmentCategory
    daily_rate: Decimal
    deposit: Decimal
    currency: str
    description: str | None = None


class ModelDetailOut(ModelOut):
    """Развёрнутое представление.

    Наследование от краткого гарантирует, что общие поля не разъедутся
    между списком и карточкой.
    """

    created_at: datetime
    units_total: int = 0
    units_available: int = 0


class StationOut(OutputSchema):
    id: int
    title: str
    address: str
    timezone: str
    is_active: bool
