"""Тесты очистки данных. Не требуют поднятого Airflow — transform это чистый Python."""

from include.orders.transform import normalize


def _order(order_id, amount, created_at):
    return {
        "order_id": order_id,
        "amount": amount,
        "currency": "RUB",
        "created_at": created_at,
    }


def test_amount_with_separators_is_parsed():
    df = normalize([_order("a", "1 200,50", "2026-01-01T10:00:00+03:00")])
    assert len(df) == 1
    assert float(df.iloc[0]["amount"]) == 1200.50


def test_rows_without_key_are_dropped():
    records = [
        _order(None, "100", "2026-01-01T10:00:00+03:00"),
        _order("b", "100", "2026-01-01T11:00:00+03:00"),
    ]
    df = normalize(records)
    assert list(df["order_id"]) == ["b"]


def test_unparsable_amount_is_dropped():
    df = normalize([_order("a", "не число", "2026-01-01T10:00:00+03:00")])
    assert df.empty


def test_deduplicates_by_order_id_keeping_latest():
    records = [
        _order("x", "100", "2026-01-01T10:00:00+03:00"),
        _order("x", "200", "2026-01-01T12:00:00+03:00"),
    ]
    df = normalize(records)
    assert len(df) == 1
    assert float(df.iloc[0]["amount"]) == 200.0  # последняя по времени
