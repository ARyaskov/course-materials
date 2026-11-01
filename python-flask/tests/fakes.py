"""Заглушки внешних зависимостей.

Не «моки»: это простые объекты, реализующие протокол и запоминающие
вызовы. Тест проверяет поведение системы, а не то, что был вызван
определённый метод определённое число раз.

Заглушка обязана уметь ломаться: путь ошибки нужно проверять так же,
как удачный путь.
"""

from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal

from depot.domain.errors import (
    NotificationError,
    PaymentUnavailable,
    QueueUnavailable,
)
from depot.domain.money import Money


@dataclass
class RecordedCall:
    name: str
    args: tuple
    kwargs: dict


class FailingQueue:
    """Очередь, которая всегда недоступна.

    Нужна ровно для одного вопроса: операция должна завершаться успешно,
    даже если задачу не удалось поставить. Состояние восстанавливается
    периодической задачей, и это поведение стоит проверить.
    """

    def enqueue(self, task: str, payload: dict) -> str:
        raise QueueUnavailable("очередь недоступна")

    def enqueue_in(self, delay_seconds: float, task: str, payload: dict) -> str:
        raise QueueUnavailable("очередь недоступна")

    def enqueue_at(self, when: datetime, task: str, payload: dict) -> str:
        raise QueueUnavailable("очередь недоступна")


class BrokenCache:
    """Кеш, недоступный на любой операции.

    Сервис должен продолжать работать: кеш ускоряет, а не обеспечивает
    правильность. Тест с этой заглушкой отвечает на вопрос, не превратился
    ли кеш в обязательную зависимость незаметно для авторов.
    """

    def get(self, key: str) -> bytes | None:
        raise ConnectionError("кеш недоступен")

    def set(self, key: str, value: bytes, ttl: int | None = None) -> None:
        raise ConnectionError("кеш недоступен")

    def delete(self, key: str) -> None:
        raise ConnectionError("кеш недоступен")

    def incr(self, key: str) -> int:
        raise ConnectionError("кеш недоступен")

    def expire(self, key: str, ttl: int) -> None:
        raise ConnectionError("кеш недоступен")

    def set_nx(self, key: str, value: str, ttl: int) -> bool:
        raise ConnectionError("кеш недоступен")

    def ping(self) -> bool:
        return False


@dataclass
class CountingNotifier:
    """Уведомитель со счётчиком и управляемыми отказами."""

    sent: list[tuple[str, str, str]] = field(default_factory=list)
    fail_times: int = 0

    def send(self, recipient: str, subject: str, body: str) -> None:
        if self.fail_times > 0:
            # отказ несколько раз подряд, затем успех: так проверяется
            # повторная попытка, а не только полный отказ
            self.fail_times -= 1
            raise NotificationError("почтовый сервер не отвечает")
        self.sent.append((recipient, subject, body))

    @property
    def last(self) -> tuple[str, str, str] | None:
        return self.sent[-1] if self.sent else None


@dataclass
class StubHold:
    id: str
    amount: Money


@dataclass
class RecordingGateway:
    """Платёжный шлюз, запоминающий ключи идемпотентности.

    Ключ важнее самого вызова: повтор операции должен приходить в шлюз
    с тем же ключом, иначе деньги удержатся дважды.
    """

    calls: list[RecordedCall] = field(default_factory=list)
    fail_times: int = 0

    def _maybe_fail(self) -> None:
        if self.fail_times > 0:
            self.fail_times -= 1
            raise PaymentUnavailable("шлюз не отвечает")

    def hold(self, amount: Money, idempotency_key: str) -> StubHold:
        self._maybe_fail()
        self.calls.append(RecordedCall("hold", (amount,), {"key": idempotency_key}))
        return StubHold(id=f"hold-{len(self.calls)}", amount=amount)

    def release(self, hold_id: str, idempotency_key: str) -> None:
        self._maybe_fail()
        self.calls.append(RecordedCall("release", (hold_id,), {"key": idempotency_key}))

    def capture(self, hold_id: str, amount: Money, idempotency_key: str) -> str:
        self._maybe_fail()
        self.calls.append(
            RecordedCall("capture", (hold_id, amount), {"key": idempotency_key})
        )
        return f"payment-{len(self.calls)}"

    def keys_for(self, name: str) -> list[str]:
        return [c.kwargs["key"] for c in self.calls if c.name == name]


def money(amount: str, currency: str = "RUB") -> Money:
    """Короткая запись денежной суммы в тестах."""
    return Money(Decimal(amount), currency)
