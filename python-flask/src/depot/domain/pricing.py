"""Расчёт стоимости аренды и штрафов.

Чистые функции: текущий момент приходит параметром, обращений к базе нет.
Поэтому тесты не подменяют системные часы и не требуют окружения.
"""

import math
from datetime import datetime
from decimal import Decimal

from depot.domain.money import Money
from depot.domain.period import Period
from depot.domain.rules import LATE_FEE_HOURS_PER_DAY


def rental_total(daily_rate: Money, period: Period, timezone: str) -> Money:
    """Стоимость аренды за период.

    Тарификация по календарным дням в часовом поясе станции: аренда с 23:00
    до 01:00 — двое суток. Ставка фиксируется на момент бронирования.
    """
    days = period.calendar_days(timezone)
    return (daily_rate * days).rounded()


def late_fee(daily_rate: Money, due_at: datetime, now: datetime) -> Money:
    """Штраф за просрочку.

    Одна двенадцатая суточной ставки за каждый час; неполный час считается
    полным. До наступления срока возврата — ноль.
    """
    if now <= due_at:
        return Money(Decimal("0"), daily_rate.currency)

    overdue_hours = math.ceil((now - due_at).total_seconds() / 3600)
    fee = daily_rate * Decimal(overdue_hours) / Decimal(LATE_FEE_HOURS_PER_DAY)
    return fee.rounded()


def deposit_hold(deposit: Money, damage_cost: Money | None = None) -> Money:
    """Сколько удержать из залога.

    Ущерб сверх залога удерживается полностью — разница выставляется отдельной
    строкой счёта, а не уменьшает удержание.
    """
    if damage_cost is None:
        return Money(Decimal("0"), deposit.currency)
    return min(damage_cost, deposit, key=lambda m: m.amount)
