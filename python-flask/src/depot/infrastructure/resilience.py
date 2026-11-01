"""Повторы и размыкатель.

Повторы обрабатывают случайные сбои, размыкатель — устойчивый отказ.
Вложенность важна: размыкатель снаружи, иначе при разомкнутой цепи будут три
попытки получить отказ вместо одной.
"""

import logging
import random
import time
from collections.abc import Callable
from datetime import datetime
from typing import TypeVar

from depot.domain.errors import CircuitOpen, TransientError
from depot.services.protocols import Clock

log = logging.getLogger(__name__)

T = TypeVar("T")


def with_retries(
    operation: Callable[[], T],
    *,
    attempts: int = 3,
    base_delay: float = 0.2,
    max_delay: float = 2.0,
    sleep: Callable[[float], None] = time.sleep,
) -> T:
    """Повтор временных ошибок с растущей паузой и разбросом.

    Разброс обязателен: без него все клиенты, получившие ошибку одновременно,
    повторят одновременно и создадут второй всплеск.
    """
    last_error: Exception | None = None

    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except TransientError as exc:
            last_error = exc
            if attempt == attempts:
                break
            delay = min(base_delay * 2 ** (attempt - 1), max_delay)
            delay *= 0.5 + random.random()
            log.warning(
                "retrying after %s (attempt %s/%s)", exc, attempt, attempts
            )
            sleep(delay)

    assert last_error is not None
    raise last_error


class CircuitBreaker:
    """Три состояния: замкнут, разомкнут, пробный.

    Состояние живёт в процессе: при нескольких воркерах каждый учится
    независимо. Общий размыкатель во внешнем хранилище сложнее и обычно
    не окупается.
    """

    def __init__(
        self,
        name: str,
        *,
        failure_threshold: int = 5,
        recovery_seconds: float = 30.0,
        clock: Clock | None = None,
    ) -> None:
        self._name = name
        self._threshold = failure_threshold
        self._recovery = recovery_seconds
        self._clock = clock
        self._failures = 0
        self._opened_at: datetime | None = None

    @property
    def is_open(self) -> bool:
        return self._opened_at is not None

    def call(self, operation: Callable[[], T]) -> T:
        if self._is_open():
            raise CircuitOpen(f"{self._name}: внешний сервис временно недоступен")
        try:
            result = operation()
        except TransientError:
            self._record_failure()
            raise
        self._record_success()
        return result

    def _now(self) -> datetime:
        if self._clock is not None:
            return self._clock.now()
        from depot.infrastructure.clock import SystemClock

        return SystemClock().now()

    def _is_open(self) -> bool:
        if self._opened_at is None:
            return False
        elapsed = (self._now() - self._opened_at).total_seconds()
        if elapsed >= self._recovery:
            self._opened_at = None  # пробная попытка
            return False
        return True

    def _record_failure(self) -> None:
        self._failures += 1
        if self._failures >= self._threshold:
            self._opened_at = self._now()
            log.warning("circuit opened for %s", self._name)

    def _record_success(self) -> None:
        if self._failures or self._opened_at:
            log.info("circuit closed for %s", self._name)
        self._failures = 0
        self._opened_at = None
