"""Правила предметной области.

Ни базы, ни приложения: модуль правил ничего внешнего не импортирует,
и эти тесты выполняются за миллисекунды. Именно они, а не сквозные
сценарии, должны покрывать граничные случаи.
"""

from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from depot.domain.enums import BookingStatus
from depot.domain.errors import InvalidPeriod, InvalidTransition
from depot.domain.money import Money
from depot.domain.period import Period
from depot.domain.pricing import late_fee, rental_total
from depot.domain.rules import (
    INSPECTION_BUFFER,
    MAX_BOOKING_DURATION,
    check_duration,
    check_transition,
    has_conflict,
)


def period(start: str, end: str) -> Period:
    return Period(datetime.fromisoformat(start), datetime.fromisoformat(end))


class TestTransitions:
    def test_pending_confirms(self) -> None:
        check_transition(BookingStatus.PENDING, BookingStatus.CONFIRMED)

    @pytest.mark.parametrize(
        "current",
        [BookingStatus.CANCELLED, BookingStatus.COMPLETED, BookingStatus.EXPIRED],
    )
    def test_final_states_are_final(self, current: BookingStatus) -> None:
        # конечное состояние — то, из которого нет переходов; проверяется
        # для каждого, а не для одного «представителя»
        with pytest.raises(InvalidTransition):
            check_transition(current, BookingStatus.CONFIRMED)

    def test_confirmed_does_not_return_to_pending(self) -> None:
        with pytest.raises(InvalidTransition):
            check_transition(BookingStatus.CONFIRMED, BookingStatus.PENDING)


class TestOverlap:
    def test_touching_periods_do_not_overlap_without_buffer(self) -> None:
        first = period("2026-03-01T10:00+03:00", "2026-03-01T12:00+03:00")
        second = period("2026-03-01T12:00+03:00", "2026-03-01T14:00+03:00")
        assert not first.overlaps(second, timedelta(0))

    def test_buffer_makes_touching_periods_conflict(self) -> None:
        # два часа на осмотр между арендами: стык впритык — это конфликт,
        # хотя интервалы формально не пересекаются
        first = period("2026-03-01T10:00+03:00", "2026-03-01T12:00+03:00")
        second = period("2026-03-01T13:00+03:00", "2026-03-01T15:00+03:00")
        assert first.overlaps(second, INSPECTION_BUFFER)

    def test_conflict_found_among_many(self) -> None:
        requested = period("2026-03-05T10:00+03:00", "2026-03-05T18:00+03:00")
        existing = [
            period("2026-03-01T10:00+03:00", "2026-03-02T10:00+03:00"),
            period("2026-03-05T16:00+03:00", "2026-03-06T10:00+03:00"),
        ]
        assert has_conflict(requested, existing)


class TestDuration:
    def test_long_period_rejected(self) -> None:
        start = datetime(2026, 3, 1, tzinfo=UTC)
        too_long = Period(start, start + MAX_BOOKING_DURATION + timedelta(hours=1))
        with pytest.raises(InvalidPeriod):
            check_duration(too_long)

    def test_exact_limit_allowed(self) -> None:
        # ровно предел — допустимо: граница включена, и это часть контракта
        start = datetime(2026, 3, 1, tzinfo=UTC)
        check_duration(Period(start, start + MAX_BOOKING_DURATION))


class TestPricing:
    def test_night_crossing_counts_two_days(self) -> None:
        # аренда с 23:00 до 01:00 — двое календарных суток по тарифу,
        # а не два часа
        rate = Money(Decimal("3000.00"), "RUB")
        night = period("2026-03-01T23:00+03:00", "2026-03-02T01:00+03:00")
        assert rental_total(rate, night, "Europe/Moscow").amount == Decimal("6000.00")

    def test_no_fee_before_due(self) -> None:
        rate = Money(Decimal("2400.00"), "RUB")
        due = datetime(2026, 3, 5, 12, tzinfo=UTC)
        assert late_fee(rate, due, due - timedelta(minutes=1)).amount == Decimal("0")

    def test_partial_hour_counts_as_full(self) -> None:
        rate = Money(Decimal("2400.00"), "RUB")
        due = datetime(2026, 3, 5, 12, tzinfo=UTC)
        fee = late_fee(rate, due, due + timedelta(minutes=1))
        # одна двенадцатая суточной ставки за начатый час
        assert fee.amount == Decimal("200.00")
