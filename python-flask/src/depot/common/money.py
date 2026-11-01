"""Денежные преобразования на границах.

Тип `Money` живёт в домене (`domain/money.py`) — он часть предметной
области. Здесь только перевод в представление и обратно: разбор строки
из запроса, форматирование для человека, работа с наименьшими единицами
для платёжного шлюза.

Ни одного `float` во всём модуле. `0.1 + 0.2` в двоичной дроби не равно
`0.3`, и на сумме счёта это перестаёт быть теоретическим замечанием.
"""

from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

#: копейки: два знака после запятой для рубля
CENTS = Decimal("0.01")

#: множитель для перевода в наименьшие единицы; шлюзы почти всегда
#: принимают целое число копеек, а не дробную сумму
MINOR_UNITS = 100

#: разделители, которые люди ставят в суммах: «1 200,50»
_STRIP = str.maketrans({" ": "", " ": "", ",": "."})


def parse_amount(raw: str) -> Decimal:
    """Разбор суммы из строки.

    Строка, а не число: JSON-число уже потеряло точность к моменту
    разбора. `Decimal` из строки сохраняет ровно то, что прислали.
    """
    try:
        value = Decimal(raw.strip().translate(_STRIP))
    except (InvalidOperation, AttributeError):
        raise ValueError(f"некорректная сумма: {raw!r}") from None

    if value.is_nan() or value.is_infinite():
        raise ValueError("сумма должна быть конечным числом")
    if value.as_tuple().exponent < -2:
        # три знака после запятой в рублёвой сумме — почти всегда ошибка
        # ввода; молча округлять её нельзя
        raise ValueError("допустимо не более двух знаков после запятой")
    return value


def round_amount(value: Decimal) -> Decimal:
    """Округление до копеек по школьному правилу.

    Указано явно: по умолчанию `Decimal` округляет к чётному
    (ROUND_HALF_EVEN). Для статистики это правильнее, для денег —
    неожиданно: 2.5 превращается в 2, а не в 3.
    """
    return value.quantize(CENTS, rounding=ROUND_HALF_UP)


def to_minor(value: Decimal) -> int:
    """Перевод в копейки для платёжного шлюза."""
    return int(round_amount(value) * MINOR_UNITS)


def from_minor(value: int) -> Decimal:
    """Обратное преобразование из копеек."""
    return (Decimal(value) / MINOR_UNITS).quantize(CENTS)


def format_amount(value: Decimal, currency: str = "RUB") -> str:
    """Сумма для человека: «3 500,00 ₽».

    Форматирование — задача представления, а не домена. В JSON уходит
    строгое `"3500.00"`, а это — для писем и печатных форм.
    """
    symbols = {"RUB": "₽", "USD": "$", "EUR": "€"}
    whole, _, fraction = f"{round_amount(value):.2f}".partition(".")
    groups = []
    while len(whole) > 3:
        groups.insert(0, whole[-3:])
        whole = whole[:-3]
    groups.insert(0, whole)
    # неразрывный пробел: сумма не должна разрываться переносом строки
    return f"{' '.join(groups)},{fraction} {symbols.get(currency, currency)}"
