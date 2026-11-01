"""Разбиение на страницы.

Смещение и предел просты, но на глубоких страницах база всё равно читает
и отбрасывает все пропущенные строки: страница 5000 обходится дороже
первой. Для списков, которые листают вглубь, есть курсор.
"""

import base64
import binascii
import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from depot.domain.errors import ValidationError

MAX_PER_PAGE = 100
DEFAULT_PER_PAGE = 20

#: предел глубины: без него запрос со страницей в миллион заставляет базу
#: прочитать двадцать миллионов строк ради двадцати
MAX_PAGE = 10_000


@dataclass(frozen=True, slots=True)
class PageRequest:
    page: int = 1
    per_page: int = DEFAULT_PER_PAGE

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.per_page

    @classmethod
    def parse(cls, args: dict[str, str]) -> "PageRequest":
        """Разбор параметров с понятными ошибками.

        Некорректное число даёт 400 с указанием поля, а не 500 из глубины
        репозитория.
        """
        page = _positive_int(args.get("page"), "page", default=1, maximum=MAX_PAGE)
        per_page = _positive_int(
            args.get("per_page"), "per_page", default=DEFAULT_PER_PAGE, maximum=MAX_PER_PAGE
        )
        return cls(page=page, per_page=per_page)


def _positive_int(raw: str | None, field: str, *, default: int, maximum: int) -> int:
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        raise ValidationError(f"{field}: ожидается целое число") from None
    if value < 1:
        raise ValidationError(f"{field}: значение должно быть положительным")
    return min(value, maximum)


def encode_cursor(payload: dict[str, Any]) -> str:
    """Курсор — непрозрачная для клиента строка.

    Она не подписана и не зашифрована, поэтому в неё кладутся только
    значения сортировки. Кодирование нужно затем, чтобы клиент не начал
    вычислять курсор сам и не привязался к внутреннему формату.
    """
    raw = json.dumps(payload, default=str, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor: str) -> dict[str, Any]:
    padding = "=" * (-len(cursor) % 4)
    try:
        raw = base64.urlsafe_b64decode(cursor + padding)
        data = json.loads(raw)
    except (binascii.Error, ValueError, UnicodeDecodeError):
        raise ValidationError("cursor: значение повреждено") from None
    if not isinstance(data, dict):
        raise ValidationError("cursor: значение повреждено")
    return data


def cursor_for(item: Any, sort_field: str) -> str:
    """Курсор следующей страницы по последнему элементу.

    В курсор идут значение сортировки и идентификатор: одного значения мало,
    когда у нескольких строк совпадает момент создания.
    """
    value = getattr(item, sort_field)
    if isinstance(value, datetime):
        value = value.isoformat()
    return encode_cursor({"v": value, "id": str(item.id)})
