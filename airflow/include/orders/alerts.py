"""Уведомление о падении задачи.

В учебном режиме алерт пишется в лог. В реальном проекте здесь был бы вызов
нотификатора (Slack / Telegram / email) — структура сообщения остаётся той же:
DAG, задача, дата, причина и ссылка на логи.
"""

from __future__ import annotations

import logging

log = logging.getLogger(__name__)


def alert_on_failure(context) -> None:
    """on_failure_callback: собирает понятный алерт из контекста запуска."""
    ti = context.get("task_instance")
    message = "\n".join([
        "ALERT: упала задача Airflow",
        f"  DAG:     {getattr(ti, 'dag_id', '?')}",
        f"  Задача:  {getattr(ti, 'task_id', '?')}",
        f"  Дата:    {context.get('ds', '?')}",
        f"  Причина: {context.get('exception', '?')}",
        f"  Логи:    {getattr(ti, 'log_url', '?')}",
    ])
    log.error(message)
