"""Базовые классы схем.

Схемы входа и выхода разделены сознательно. Общий класс приводит к тому,
что поле, добавленное для ответа, начинает приниматься в запросе.
"""

from typing import Any

from pydantic import BaseModel, ConfigDict


class InputSchema(BaseModel):
    """Всё, что приходит от клиента."""

    model_config = ConfigDict(
        # лишнее поле — ошибка, а не тишина: опечатка в имени поля иначе
        # выглядит как «сервер проигнорировал мои данные»
        extra="forbid",
        # строки обрезаются до проверки: " " не пройдёт min_length
        str_strip_whitespace=True,
        populate_by_name=True,
    )


class OutputSchema(BaseModel):
    """Всё, что уходит клиенту."""

    model_config = ConfigDict(
        # чтение атрибутов модели SQLAlchemy напрямую
        from_attributes=True,
        # неизвестные поля отбрасываются: случайно добавленный в модель
        # столбец не утечёт в ответ
        extra="ignore",
    )

    def public(self) -> dict[str, Any]:
        """Словарь для ответа.

        mode="json" превращает Decimal и datetime в строки здесь, а не
        в сериализаторе Flask: схема остаётся единственным местом, где
        решается форма ответа.
        """
        return self.model_dump(mode="json")


class PageMeta(OutputSchema):
    """Метаданные страницы.

    Отдаётся номер страницы и её размер, а не смещение: клиент показывает
    «страница 3 из 12», и пересчитывать это на его стороне незачем.
    """

    total: int
    page: int
    per_page: int

    @property
    def pages(self) -> int:
        return max(1, -(-self.total // self.per_page))


class PageResponse(OutputSchema):
    """Оболочка списочного ответа.

    Список верхним уровнем не отдаётся: добавить к нему метаданные
    постранично уже нельзя без слома клиентов.
    """

    items: list[Any]
    meta: PageMeta
