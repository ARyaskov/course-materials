"""Transform: привести типы, отсеять пустое, убрать дубли.

Чистый Python поверх pandas — никакого Airflow, поэтому функция тестируется
как обычный код (см. tests/test_transform.py). Сюда попадает только
техническая очистка; бизнес-логика (категории, маржа, правила) живёт в витрине.
"""

from __future__ import annotations

import pandas as pd

COLUMNS = ["order_id", "amount", "currency", "created_at"]


def normalize(records: list[dict]) -> pd.DataFrame:
    """Из сырых записей получить очищенный, типизированный, дедуплицированный DataFrame."""
    df = pd.DataFrame(records, columns=COLUMNS)

    # 1. Приведение типов. errors="coerce" превращает битые значения в пропуск,
    #    а не в исключение, — одна плохая строка не валит всю загрузку.
    df["amount"] = pd.to_numeric(_clean_amount(df["amount"]), errors="coerce")
    df["created_at"] = pd.to_datetime(df["created_at"], errors="coerce", utc=True)

    # 2. Обработка пустых: без ключа, суммы или даты строка бесполезна.
    df = df.dropna(subset=["order_id", "amount", "created_at"])

    # 3. Дедупликация по бизнес-ключу, оставляем самую свежую версию.
    df = df.sort_values("created_at").drop_duplicates("order_id", keep="last")

    return df.reset_index(drop=True)


def _clean_amount(series: pd.Series) -> pd.Series:
    """Нормализовать строку суммы: убрать пробелы-разделители, запятую -> точка.

    Так "1 200,50" становится разбираемым числом, а не пропуском. Регулярка \\s
    снимает любые пробелы, включая неразрывный.
    """
    return (
        series.astype("string")
        .str.replace(r"\s", "", regex=True)
        .str.replace(",", ".", regex=False)
    )
