"""Сборка компонентов.

Единственное место, знающее о конфигурации и о конкретных классах. Сервисы
зависят от протоколов и не знают, какая реализация подставлена.

Ветка с исключением обязательна: опечатка в переменной окружения должна ронять
приложение при старте, а не приводить к тихому выбору умолчания.
"""

from collections.abc import Mapping
from datetime import timedelta
from typing import Any

from depot.infrastructure.cache_redis import MemoryCache, RedisCache, ResilientCache
from depot.infrastructure.clock import SystemClock
from depot.infrastructure.memory_queue import MemoryTaskQueue
from depot.infrastructure.notifier import LoggingNotifier, MemoryNotifier, SmtpNotifier
from depot.infrastructure.payment import FakePaymentGateway, HttpPaymentGateway
from depot.infrastructure.queue_rq import RqTaskQueue
from depot.infrastructure.resilience import CircuitBreaker
from depot.infrastructure.storage import (
    LocalFileStorage,
    MemoryFileStorage,
    S3FileStorage,
)
from depot.services.protocols import (
    Cache,
    Clock,
    FileStorage,
    Notifier,
    PaymentGateway,
    TaskQueue,
)
from depot.services.tokens import TokenService


def build_queue(config: Mapping[str, Any]) -> TaskQueue:
    backend = config["QUEUE_BACKEND"]
    if backend == "redis":
        return RqTaskQueue(config["REDIS_URL"])
    if backend == "memory":
        return MemoryTaskQueue()
    raise RuntimeError(f"неизвестный backend очереди: {backend}")


def build_cache(config: Mapping[str, Any]) -> Cache:
    backend = config["CACHE_BACKEND"]
    if backend == "redis":
        inner: Cache = RedisCache(
            config["REDIS_URL"], default_ttl=config["CACHE_DEFAULT_TTL"]
        )
    elif backend == "memory":
        inner = MemoryCache()
    else:
        raise RuntimeError(f"неизвестный backend кеша: {backend}")
    return ResilientCache(inner)


def build_storage(config: Mapping[str, Any]) -> FileStorage:
    backend = config["STORAGE_BACKEND"]
    if backend == "s3":
        return S3FileStorage(
            endpoint=config["S3_ENDPOINT"],
            bucket=config["S3_BUCKET"],
            access_key=config["S3_ACCESS_KEY"],
            secret_key=config["S3_SECRET_KEY"],
        )
    if backend == "local":
        return LocalFileStorage(config["STORAGE_PATH"])
    if backend == "memory":
        return MemoryFileStorage()
    raise RuntimeError(f"неизвестный backend хранилища: {backend}")


def build_notifier(config: Mapping[str, Any]) -> Notifier:
    backend = config["NOTIFICATIONS_BACKEND"]
    if backend == "smtp":
        return SmtpNotifier(config["SMTP_URL"])
    if backend == "log":
        return LoggingNotifier()
    if backend == "memory":
        return MemoryNotifier()
    raise RuntimeError(f"неизвестный backend уведомлений: {backend}")


def build_payment(config: Mapping[str, Any]) -> PaymentGateway:
    backend = config["PAYMENT_BACKEND"]
    if backend == "http":
        return HttpPaymentGateway(
            config["PAYMENT_GATEWAY_URL"],
            config["PAYMENT_API_KEY"],
            breaker=CircuitBreaker("payment"),
        )
    if backend == "fake":
        return FakePaymentGateway()
    raise RuntimeError(f"неизвестный backend платежей: {backend}")


def build_clock(config: Mapping[str, Any]) -> Clock:
    return SystemClock()


def build_tokens(config: Mapping[str, Any], clock: Clock) -> TokenService:
    """Служба токенов с набором ключей.

    Ключей в наборе может быть два: действующий, которым подписываются новые
    токены, и прошлый, который ещё принимается при проверке. Без этого смена
    ключа обрывает все живые сессии в момент выкладки.
    """
    keys = {config["TOKEN_KEY_ID"]: config["SECRET_KEY"]}
    previous = config.get("SECRET_KEY_PREVIOUS")
    if previous:
        keys[config["TOKEN_KEY_ID_PREVIOUS"]] = previous

    return TokenService(
        keys=keys,
        current_key_id=config["TOKEN_KEY_ID"],
        issuer=config["TOKEN_ISSUER"],
        audience=config["TOKEN_AUDIENCE"],
        access_ttl=timedelta(seconds=config["ACCESS_TOKEN_TTL_SECONDS"]),
        refresh_ttl=timedelta(seconds=config["REFRESH_TOKEN_TTL_SECONDS"]),
        clock=clock,
    )


def build_components(config: Mapping[str, Any]) -> dict[str, Any]:
    clock = build_clock(config)
    return {
        "queue": build_queue(config),
        "cache": build_cache(config),
        "storage": build_storage(config),
        "notifier": build_notifier(config),
        "payment": build_payment(config),
        "clock": clock,
        # часы передаются готовым объектом: две реализации времени в одном
        # приложении дали бы расхождение сроков жизни токенов
        "tokens": build_tokens(config, clock),
    }
