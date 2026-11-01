"""Клиент платёжного шлюза.

Чужой формат не выходит за границы модуля: наружу отдаётся доменный объект.
При изменении их API правится один файл.
"""

import logging
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, NotRequired, TypedDict

import httpx

from depot.domain.errors import (
    ConfigurationError,
    DepotError,
    InsufficientFunds,
    IntegrationError,
    PaymentUnavailable,
)
from depot.domain.money import Money
from depot.infrastructure.resilience import CircuitBreaker, with_retries

log = logging.getLogger(__name__)


class GatewayHoldRequest(TypedDict):
    """Форма чужого API — записана как есть, а не в нашем стиле."""

    amount: str
    currency: str
    idempotencyKey: str
    description: NotRequired[str]


@dataclass(frozen=True, slots=True)
class PaymentHold:
    id: str
    amount: Money
    expires_at: datetime


class HttpPaymentGateway:
    def __init__(
        self,
        base_url: str,
        api_key: str,
        *,
        timeout_seconds: float = 3.0,
        breaker: CircuitBreaker | None = None,
    ) -> None:
        self._client = httpx.Client(
            base_url=base_url,
            # четыре таймаута решают разные задачи; без pool исчерпание
            # пула даёт бесконечное ожидание
            timeout=httpx.Timeout(
                connect=2.0, read=timeout_seconds, write=timeout_seconds, pool=1.0
            ),
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
            headers={
                "Authorization": f"Bearer {api_key}",
                "User-Agent": "depot-api/1.0",
                "Accept": "application/json",
            },
        )
        self._breaker = breaker or CircuitBreaker("payment")

    def hold(self, amount: Money, idempotency_key: str) -> PaymentHold:
        # размыкатель снаружи повторов: при разомкнутой цепи попытки не идут
        return self._breaker.call(
            lambda: with_retries(
                lambda: self._do_hold(amount, idempotency_key), attempts=3
            )
        )

    def release(self, hold_id: str, idempotency_key: str) -> None:
        self._breaker.call(
            lambda: with_retries(
                lambda: self._post(f"/v2/holds/{hold_id}/release", {"idempotencyKey": idempotency_key}),
                attempts=3,
            )
        )

    def capture(self, hold_id: str, amount: Money, idempotency_key: str) -> str:
        data = self._breaker.call(
            lambda: with_retries(
                lambda: self._post(
                    f"/v2/holds/{hold_id}/capture",
                    {
                        "amount": str(amount.amount),
                        "currency": amount.currency,
                        "idempotencyKey": idempotency_key,
                    },
                ),
                attempts=3,
            )
        )
        return str(data["id"])

    def _do_hold(self, amount: Money, idempotency_key: str) -> PaymentHold:
        payload: GatewayHoldRequest = {
            "amount": str(amount.amount),
            "currency": amount.currency,
            "idempotencyKey": idempotency_key,
        }
        data = self._post("/v2/holds", dict(payload))
        return PaymentHold(
            id=str(data["id"]),
            amount=Money(Decimal(str(data["amount"])), str(data["currency"])),
            expires_at=datetime.fromisoformat(str(data["expiresAt"])),
        )

    def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        started = time.perf_counter()
        outcome = "ok"
        try:
            response = self._client.post(path, json=payload)
            response.raise_for_status()
            return dict(response.json())
        except httpx.TimeoutException as exc:
            outcome = "timeout"
            raise PaymentUnavailable("платёжный шлюз не ответил вовремя") from exc
        except httpx.ConnectError as exc:
            outcome = "unavailable"
            raise PaymentUnavailable("нет соединения с платёжным шлюзом") from exc
        except httpx.HTTPStatusError as exc:
            outcome = "error"
            raise self._translate_status(exc) from exc
        except ValueError as exc:
            outcome = "malformed"
            raise IntegrationError("шлюз вернул неразбираемый ответ") from exc
        finally:
            elapsed = time.perf_counter() - started
            # ни тело запроса, ни ответ в журнал не пишутся: там платёжные данные
            log.info(
                "external call POST %s",
                path,
                extra={"service": "payment", "outcome": outcome,
                       "duration_ms": round(elapsed * 1000, 1)},
            )

    def _translate_status(self, exc: httpx.HTTPStatusError) -> DepotError:
        status = exc.response.status_code
        if status >= 500:
            return PaymentUnavailable("платёжный шлюз вернул ошибку")
        if status == 429:
            return PaymentUnavailable("платёжный шлюз ограничил частоту запросов")
        if status == 402:
            # доменная ситуация, а не сбой: клиент может пополнить счёт
            return InsufficientFunds("недостаточно средств")
        if status in (401, 403):
            # постоянная ошибка: повтор не поможет, нужен человек
            return ConfigurationError("платёжный шлюз отклонил учётные данные")
        return IntegrationError(f"шлюз отклонил запрос: {status}")


@dataclass
class HoldCall:
    amount: Money
    key: str


class FakePaymentGateway:
    """Заглушка, умеющая ломаться.

    Заглушка, которая всегда успешна и мгновенна, даёт зелёные тесты
    и не проверяет ни одной ветки обработки ошибок.
    """

    def __init__(self, behaviour: str = "ok", fail_times: int = 0) -> None:
        self.behaviour = behaviour
        self.fail_times = fail_times
        self.calls: list[HoldCall] = []

    def hold(self, amount: Money, idempotency_key: str) -> PaymentHold:
        self.calls.append(HoldCall(amount=amount, key=idempotency_key))

        if self.fail_times > 0:
            self.fail_times -= 1
            raise PaymentUnavailable("временный сбой")

        if self.behaviour == "timeout":
            raise PaymentUnavailable("шлюз не ответил вовремя")
        if self.behaviour == "insufficient":
            raise InsufficientFunds("недостаточно средств")
        if self.behaviour == "ok":
            from uuid import uuid4

            return PaymentHold(
                id=f"hold_{uuid4().hex[:8]}",
                amount=amount,
                expires_at=datetime.now(tz=None).astimezone() + timedelta(hours=1),
            )

        raise AssertionError(f"неизвестное поведение: {self.behaviour}")

    def release(self, hold_id: str, idempotency_key: str) -> None:
        return None

    def capture(self, hold_id: str, amount: Money, idempotency_key: str) -> str:
        return f"charge_{hold_id}"
