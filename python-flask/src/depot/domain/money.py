"""Денежная величина.

Считать с полной точностью, округлять один раз — при формировании суммы счёта.
"""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

KOPECK = Decimal("0.01")
DEFAULT_CURRENCY = "RUB"


@dataclass(frozen=True, slots=True)
class Money:
    amount: Decimal
    currency: str = DEFAULT_CURRENCY

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError("сумма не может быть отрицательной")
        if len(self.currency) != 3:
            raise ValueError("код валюты состоит из трёх символов")

    def __add__(self, other: "Money") -> "Money":
        self._same_currency(other)
        return Money(self.amount + other.amount, self.currency)

    def __sub__(self, other: "Money") -> "Money":
        self._same_currency(other)
        return Money(self.amount - other.amount, self.currency)

    def __mul__(self, factor: int | Decimal) -> "Money":
        return Money(self.amount * Decimal(factor), self.currency)

    def __truediv__(self, divisor: int | Decimal) -> "Money":
        return Money(self.amount / Decimal(divisor), self.currency)

    def rounded(self) -> "Money":
        """Округление до копеек арифметическим правилом.

        Встроенное округление к чётному расходится с бухгалтерским ожиданием,
        поэтому правило задано явно.
        """
        return Money(self.amount.quantize(KOPECK, rounding=ROUND_HALF_UP), self.currency)

    def __str__(self) -> str:
        return f"{self.amount} {self.currency}"

    def _same_currency(self, other: "Money") -> None:
        if self.currency != other.currency:
            raise ValueError(f"разные валюты: {self.currency} и {other.currency}")


ZERO = Money(Decimal("0"))
