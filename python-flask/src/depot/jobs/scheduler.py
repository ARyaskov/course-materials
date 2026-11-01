"""Расписание регламентных задач.

Расписание описано данными, а не кодом: список читается целиком, и добавление
задачи не требует правки логики планировщика.

Планировщик запускается в одном экземпляре. Несколько копий поставят одну
и ту же задачу несколько раз, поэтому запуск защищён коротким замком в кеше:
это дешевле отдельного координатора и достаточно для регламентных работ,
каждая из которых и так идемпотентна.
"""

import logging
import time
from dataclasses import dataclass

from depot.jobs.context import component, worker_app

log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class Schedule:
    task: str
    every_seconds: int
    description: str


SCHEDULE: tuple[Schedule, ...] = (
    Schedule(
        "depot.jobs.bookings.expire_stale_holds",
        60,
        "снять просроченные удержания",
    ),
    Schedule(
        "depot.jobs.billing.charge_late_fees",
        3600,
        "начислить штрафы за просрочку",
    ),
    Schedule(
        "depot.jobs.billing.release_expired_holds",
        900,
        "вернуть удержания по отменённым броням",
    ),
    Schedule(
        "depot.jobs.maintenance.purge_expired_sessions",
        86_400,
        "удалить просроченные сессии",
    ),
    Schedule(
        "depot.jobs.maintenance.purge_idempotency_records",
        86_400,
        "удалить устаревшие ключи идемпотентности",
    ),
)

#: замок живёт чуть меньше интервала: если планировщик умрёт сразу после
#: постановки, следующий экземпляр подхватит работу вовремя
LOCK_MARGIN = 5


def tick(now: float | None = None) -> list[str]:
    """Один проход планировщика.

    Возвращает поставленные задачи — это делает функцию проверяемой:
    тест вызывает её с фиксированным моментом и сверяет список.
    """
    moment = int(now if now is not None else time.time())
    queue = component("queue")
    cache = component("cache")
    scheduled: list[str] = []

    for item in SCHEDULE:
        # окно выравнивается по интервалу: все экземпляры планировщика
        # претендуют на один и тот же ключ, и выигрывает ровно один
        window = moment // item.every_seconds
        key = f"cron:{item.task}:{window}"
        if not cache.set_nx(key, "1", ttl=item.every_seconds - LOCK_MARGIN):
            continue

        queue.enqueue(item.task, {})
        scheduled.append(item.task)
        log.info("scheduled %s", item.task, extra={"description": item.description})

    return scheduled


def run_forever(interval: int = 30) -> None:
    """Цикл планировщика для отдельного процесса."""
    with worker_app().app_context():
        log.info("scheduler started", extra={"tasks": len(SCHEDULE)})
        while True:
            try:
                tick()
            except Exception:
                # падение одного прохода не должно останавливать планировщик:
                # следующая итерация повторит попытку
                log.exception("scheduler tick failed")
            time.sleep(interval)
