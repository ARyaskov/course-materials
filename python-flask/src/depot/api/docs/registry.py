"""Реестр описаний обработчиков.

Описание живёт рядом с кодом, который оно описывает. Отдельный YAML-файл
расходится с реальностью на второй неделе: маршрут переименован, файл нет.
"""

from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, TypeVar

F = TypeVar("F", bound=Callable[..., Any])


@dataclass(slots=True)
class Endpoint:
    summary: str
    tags: list[str] = field(default_factory=list)
    status: int = 200
    public: bool = False
    request_schema: type | None = None
    response_schema: type | None = None
    deprecated: bool = False


#: ключ — полное имя функции обработчика; blueprint при регистрации даёт
#: маршруту имя вида "v1.create_booking", по нему описание и находится
REGISTRY: dict[str, Endpoint] = {}


def document(
    *,
    summary: str,
    tags: list[str] | None = None,
    status: int = 200,
    public: bool = False,
    request_schema: type | None = None,
    response_schema: type | None = None,
    deprecated: bool = False,
) -> Callable[[F], F]:
    """Пометка обработчика для генератора документа.

    Декоратор ничего не оборачивает: он только регистрирует данные
    и возвращает исходную функцию. Лишний уровень вызова на каждом
    запросе ради документации не нужен.
    """

    def decorator(func: F) -> F:
        REGISTRY[func.__name__] = Endpoint(
            summary=summary,
            tags=tags or [],
            status=status,
            public=public,
            request_schema=request_schema,
            response_schema=response_schema,
            deprecated=deprecated,
        )
        return func

    return decorator
