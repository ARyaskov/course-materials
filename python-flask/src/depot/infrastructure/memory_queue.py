"""Очередь в памяти — для тестов и локального запуска без Redis."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from depot.domain.errors import QueueUnavailable


@dataclass(frozen=True, slots=True)
class EnqueuedTask:
    task: str
    payload: dict[str, str]


@dataclass(frozen=True, slots=True)
class ScheduledTask:
    when: datetime
    task: str
    payload: dict[str, str]


class MemoryTaskQueue:
    def __init__(self) -> None:
        self.enqueued: list[EnqueuedTask] = []
        self.scheduled: list[ScheduledTask] = []
        self.fail = False

    def _check(self) -> None:
        if self.fail:
            raise QueueUnavailable("очередь задач недоступна")

    def enqueue(self, task: str, payload: Mapping[str, str]) -> str:
        self._check()
        self.enqueued.append(EnqueuedTask(task, dict(payload)))
        return uuid4().hex

    def enqueue_in(
        self, delay_seconds: float, task: str, payload: Mapping[str, str]
    ) -> str:
        self._check()
        when = datetime.now(UTC) + timedelta(seconds=delay_seconds)
        self.scheduled.append(ScheduledTask(when, task, dict(payload)))
        return uuid4().hex

    def enqueue_at(self, when: datetime, task: str, payload: Mapping[str, str]) -> str:
        self._check()
        self.scheduled.append(ScheduledTask(when, task, dict(payload)))
        return uuid4().hex

    def run_all(self) -> None:
        """Выполнить накопленные задачи синхронно.

        Приём для одного-двух сквозных сценариев: основной способ — проверка
        факта постановки, иначе тест перестаёт проверять асинхронность.
        """
        import importlib

        pending, self.enqueued = self.enqueued, []
        for item in pending:
            module_name, _, func_name = item.task.rpartition(".")
            module = importlib.import_module(module_name)
            func = getattr(module, func_name)
            inner = getattr(func, "__wrapped__", func)
            inner(**item.payload)

    def clear(self) -> None:
        self.enqueued.clear()
        self.scheduled.clear()
