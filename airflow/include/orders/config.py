"""Общие настройки проекта orders__daily_etl.

Модуль намеренно не импортирует Airflow и тяжёлые библиотеки — он содержит
только константы, поэтому импортируется мгновенно.
"""

from __future__ import annotations

# Идентификаторы подключений Airflow.
# Заданы в docker-compose.yaml через переменные AIRFLOW_CONN_*.
WAREHOUSE_CONN_ID = "warehouse"   # PostgreSQL: схемы raw / staging / marts
OBJECT_STORE_CONN_ID = "minio"    # S3-совместимое хранилище (MinIO)

# Базовый адрес сырого слоя в объектном хранилище.
RAW_BUCKET = "s3://raw"

# Источник данных.
# По умолчанию (None) проект работает в учебном режиме и генерирует
# синтетические заказы, чтобы запускаться без внешнего API.
# Чтобы подключить реальный API, укажите его базовый адрес здесь
# (или подставьте из переменной окружения / Variable).
ORDERS_API_BASE_URL: str | None = None
