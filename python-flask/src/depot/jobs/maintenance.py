"""Регламентные работы.

Уборка данных — не украшение: таблица сессий и таблица ключей
идемпотентности растут со скоростью трафика, и без чистки они через год
занимают больше, чем все полезные данные вместе.
"""

import logging

from depot.jobs.context import component, job
from depot.services.uow import make_uow

log = logging.getLogger(__name__)

#: удаление идёт порциями: DELETE на миллион строк держит блокировки
#: и раздувает журнал упреждающей записи
CLEANUP_BATCH = 5000


@job
def purge_expired_sessions() -> int:
    now = component("clock").now()
    with make_uow() as uow:
        removed = uow.sessions.delete_expired(now, CLEANUP_BATCH)
    if removed:
        log.info("expired sessions removed", extra={"count": removed})
    return removed


@job
def purge_idempotency_records() -> int:
    """Удаление ключей идемпотентности старше срока хранения.

    Срок хранения — часть контракта: повтор запроса позже этого времени
    выполнится заново. Клиенту это сказано в документации, и укорачивать
    срок молча нельзя.
    """
    now = component("clock").now()
    with make_uow() as uow:
        removed = uow.idempotency.delete_expired(now, CLEANUP_BATCH)
    if removed:
        log.info("idempotency records removed", extra={"count": removed})
    return removed
