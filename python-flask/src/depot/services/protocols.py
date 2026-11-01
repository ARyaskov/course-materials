"""Протоколы зависимостей.

Объявлены рядом с потребителем: они описывают, что нужно сервису, а не что
умеет реализация. Благодаря этому слой инфраструктуры зависит от слоя сервисов,
а не наоборот, и доменные сценарии тестируются без единой строчки
инфраструктурного кода.

Протокол перечисляет только используемые методы: заглушка в тесте реализует
три метода, а не двадцать.
"""

from collections.abc import Iterator, Mapping
from datetime import datetime
from typing import IO, Protocol

from depot.domain.money import Money


class Clock(Protocol):
    """Источник текущего времени.

    Зависимость, а не прямой вызов: тест подставляет нужный момент вместо
    подмены системных часов и ожидания.
    """

    def now(self) -> datetime: ...


class TaskQueue(Protocol):
    def enqueue(self, task: str, payload: Mapping[str, str]) -> str: ...

    def enqueue_in(
        self, delay_seconds: float, task: str, payload: Mapping[str, str]
    ) -> str: ...

    def enqueue_at(
        self, when: datetime, task: str, payload: Mapping[str, str]
    ) -> str: ...


class Cache(Protocol):
    def get(self, key: str) -> bytes | None: ...

    def set(self, key: str, value: bytes, ttl: int | None = None) -> None: ...

    def delete(self, key: str) -> None: ...

    def incr(self, key: str) -> int: ...

    def expire(self, key: str, ttl: int) -> None: ...

    def set_nx(self, key: str, value: str, ttl: int) -> bool: ...

    def ping(self) -> bool: ...


class Notifier(Protocol):
    def send(self, recipient: str, subject: str, body: str) -> None: ...


class FileStorage(Protocol):
    def put(self, key: str, content: bytes, *, content_type: str) -> None: ...

    def get(self, key: str) -> bytes: ...

    def open(self, key: str) -> IO[bytes]: ...

    def delete(self, key: str) -> None: ...

    def delete_quietly(self, key: str) -> None: ...

    def exists(self, key: str) -> bool: ...

    def list_keys(self, prefix: str) -> Iterator[str]: ...

    def presigned_url(self, key: str, expires_in: int) -> str | None: ...


class PaymentHold(Protocol):
    @property
    def id(self) -> str: ...

    @property
    def amount(self) -> Money: ...


class PaymentGateway(Protocol):
    def hold(self, amount: Money, idempotency_key: str) -> PaymentHold: ...

    def release(self, hold_id: str, idempotency_key: str) -> None: ...

    def capture(self, hold_id: str, amount: Money, idempotency_key: str) -> str: ...
