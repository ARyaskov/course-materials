"""Кеш на Redis и устойчивая обёртка над ним.

Кеш в памяти процесса обманчив: у четырёх воркеров четыре независимых словаря,
и сброс в одном не затрагивает остальные. Кеш живёт во внешнем хранилище.
"""

import json
import logging
import random
from typing import Any

from redis import Redis
from redis.exceptions import RedisError

from depot.domain.errors import CacheUnavailable
from depot.services.protocols import Cache

log = logging.getLogger(__name__)


def jittered_ttl(base: int, spread: float = 0.1) -> int:
    """Разброс срока жизни.

    Ключи, созданные одновременно, иначе истекут одновременно и дадут
    всплеск нагрузки.
    """
    return int(base * (1 + random.uniform(-spread, spread)))


class RedisCache:
    def __init__(self, url: str, prefix: str = "depot", default_ttl: int = 300) -> None:
        self._url = url
        self._prefix = prefix
        self._default_ttl = default_ttl
        self._client: Redis | None = None

    @property
    def client(self) -> Redis:
        # ленивое подключение, как и у очереди
        if self._client is None:
            self._client = Redis.from_url(self._url, decode_responses=False)
        return self._client

    def _key(self, key: str) -> str:
        return key if key.startswith(self._prefix + ":") else f"{self._prefix}:{key}"

    def get(self, key: str) -> bytes | None:
        try:
            return self.client.get(self._key(key))
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def set(self, key: str, value: bytes, ttl: int | None = None) -> None:
        try:
            self.client.set(self._key(key), value, ex=ttl or self._default_ttl)
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def delete(self, key: str) -> None:
        try:
            self.client.delete(self._key(key))
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def incr(self, key: str) -> int:
        try:
            return int(self.client.incr(self._key(key)))
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def expire(self, key: str, ttl: int) -> None:
        try:
            self.client.expire(self._key(key), ttl)
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def set_nx(self, key: str, value: str, ttl: int) -> bool:
        """Установка только при отсутствии ключа.

        Атомарна: из двух планировщиков истину получит ровно один.
        """
        try:
            return bool(self.client.set(self._key(key), value, nx=True, ex=ttl))
        except RedisError as exc:
            raise CacheUnavailable("кеш недоступен") from exc

    def ping(self) -> bool:
        try:
            return bool(self.client.ping())
        except RedisError:
            return False


class ResilientCache:
    """Кеш — вспомогательная зависимость.

    Ошибка чтения превращается в промах, ошибка записи — в её отсутствие:
    данные всегда можно взять из источника. Тот же приём нельзя применить
    к базе или платёжному шлюзу.
    """

    def __init__(self, inner: Cache) -> None:
        self._inner = inner

    def get(self, key: str) -> bytes | None:
        try:
            return self._inner.get(key)
        except CacheUnavailable:
            log.warning("cache read failed", extra={"cache_key": key})
            return None

    def set(self, key: str, value: bytes, ttl: int | None = None) -> None:
        try:
            self._inner.set(key, value, ttl)
        except CacheUnavailable:
            log.warning("cache write failed", extra={"cache_key": key})

    def delete(self, key: str) -> None:
        try:
            self._inner.delete(key)
        except CacheUnavailable:
            log.warning("cache delete failed", extra={"cache_key": key})

    def incr(self, key: str) -> int:
        return self._inner.incr(key)

    def expire(self, key: str, ttl: int) -> None:
        try:
            self._inner.expire(key, ttl)
        except CacheUnavailable:
            pass

    def set_nx(self, key: str, value: str, ttl: int) -> bool:
        return self._inner.set_nx(key, value, ttl)

    def ping(self) -> bool:
        return self._inner.ping()

    def get_json(self, key: str) -> Any | None:
        raw = self.get(key)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            # формат мог измениться между версиями кода: промах лучше исключения
            log.warning("corrupted cache entry", extra={"cache_key": key})
            return None

    def set_json(self, key: str, value: Any, ttl: int | None = None) -> None:
        self.set(key, json.dumps(value, ensure_ascii=False, default=str).encode(), ttl)


class MemoryCache:
    """Реализация для тестов и локального запуска без Redis."""

    def __init__(self) -> None:
        self.items: dict[str, bytes] = {}
        self.fail = False

    def _check(self) -> None:
        if self.fail:
            raise CacheUnavailable("кеш недоступен")

    def get(self, key: str) -> bytes | None:
        self._check()
        return self.items.get(key)

    def set(self, key: str, value: bytes, ttl: int | None = None) -> None:
        self._check()
        self.items[key] = value

    def delete(self, key: str) -> None:
        self._check()
        self.items.pop(key, None)

    def incr(self, key: str) -> int:
        self._check()
        value = int(self.items.get(key, b"0")) + 1
        self.items[key] = str(value).encode()
        return value

    def expire(self, key: str, ttl: int) -> None:
        self._check()

    def set_nx(self, key: str, value: str, ttl: int) -> bool:
        self._check()
        if key in self.items:
            return False
        self.items[key] = value.encode()
        return True

    def ping(self) -> bool:
        return not self.fail
