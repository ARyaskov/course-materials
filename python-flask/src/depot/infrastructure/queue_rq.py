"""Очередь задач на RQ.

Приложение зависит от протокола `TaskQueue`, а не от библиотеки: смена
инструмента — новая реализация и одна строка в функции сборки.

Полезная нагрузка — только простые значения: она сериализуется в JSON
и пересекает границу процесса. Её формат — контракт между версиями кода.
"""

from collections.abc import Mapping
from datetime import datetime, timedelta

from redis import Redis
from redis.exceptions import RedisError
from rq import Queue

from depot.domain.errors import QueueUnavailable

DEFAULT_TIMEOUTS: dict[str, int] = {
    "depot.jobs.imports.import_catalog": 1800,
    "depot.jobs.billing.charge_late_fees": 900,
}


class RqTaskQueue:
    def __init__(self, redis_url: str, queue_name: str = "default") -> None:
        self._redis_url = redis_url
        self._queue_name = queue_name
        self._queue: Queue | None = None

    @property
    def _q(self) -> Queue:
        # ленивое подключение: соединение, открытое до форка воркеров,
        # наследуется всеми процессами и ломается
        if self._queue is None:
            self._queue = Queue(
                self._queue_name, connection=Redis.from_url(self._redis_url)
            )
        return self._queue

    def enqueue(self, task: str, payload: Mapping[str, str]) -> str:
        try:
            # payload передаётся именованными аргументами, а не одним словарём:
            # так сигнатура задачи остаётся читаемой, а очередь в памяти
            # вызывает ту же функцию тем же способом
            job = self._q.enqueue(
                task, kwargs=dict(payload), job_timeout=DEFAULT_TIMEOUTS.get(task, 300)
            )
        except RedisError as exc:
            raise QueueUnavailable("очередь задач недоступна") from exc
        return str(job.id)

    def enqueue_in(
        self, delay_seconds: float, task: str, payload: Mapping[str, str]
    ) -> str:
        try:
            job = self._q.enqueue_in(
                timedelta(seconds=delay_seconds), task, kwargs=dict(payload)
            )
        except RedisError as exc:
            raise QueueUnavailable("очередь задач недоступна") from exc
        return str(job.id)

    def enqueue_at(
        self, when: datetime, task: str, payload: Mapping[str, str]
    ) -> str:
        try:
            job = self._q.enqueue_at(when, task, kwargs=dict(payload))
        except RedisError as exc:
            raise QueueUnavailable("очередь задач недоступна") from exc
        return str(job.id)

    def size(self) -> int:
        return len(self._q)
