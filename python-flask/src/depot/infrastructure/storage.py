"""Хранилище файлов: локальное, S3-совместимое и в памяти.

Локальный диск не подходит приложению, работающему больше чем в одном
экземпляре: файл виден только тому, кто его принял. Он остаётся для разработки,
рабочая конфигурация складывает файлы в объектное хранилище.
"""

import os
import uuid
from collections.abc import Iterator
from datetime import UTC, datetime
from io import BytesIO
from pathlib import Path
from typing import IO, Final

from depot.domain.errors import (
    NotFound,
    PayloadTooLarge,
    PermissionDenied,
    StorageUnavailable,
    UnsupportedMediaType,
)

#: сигнатуры в первых байтах: расширение и заголовок задаёт клиент
SIGNATURES: Final[dict[bytes, str]] = {
    b"\xff\xd8\xff": "image/jpeg",
    b"\x89PNG\r\n\x1a\n": "image/png",
    b"RIFF": "image/webp",
}

MEDIA_SUFFIXES: Final[dict[str, str]] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


def detect_image_type(head: bytes) -> str:
    for signature, media_type in SIGNATURES.items():
        if head.startswith(signature):
            return media_type
    raise UnsupportedMediaType("поддерживаются только JPEG, PNG и WebP")


def read_limited(stream: IO[bytes], limit: int) -> bytes:
    """Чтение порциями с проверкой накопленного размера.

    Проверка после полного чтения бессмысленна: память уже занята.
    """
    chunks: list[bytes] = []
    total = 0
    while chunk := stream.read(64 * 1024):
        total += len(chunk)
        if total > limit:
            raise PayloadTooLarge(f"файл больше {limit // 1024 // 1024} МБ")
        chunks.append(chunk)
    return b"".join(chunks)


def storage_key(original_name: str, media_type: str, prefix: str = "damage") -> str:
    """Имя генерируется; оригинальное сохраняется как метаданные.

    Снимает вопросы выхода из каталога, недопустимых символов, переносимости
    и коллизий. Разбиение по датам нужно файловой системе.
    """
    suffix = MEDIA_SUFFIXES[media_type]
    today = datetime.now(UTC)
    return f"{prefix}/{today:%Y/%m}/{uuid.uuid4().hex}{suffix}"


class LocalFileStorage:
    def __init__(self, root: Path | str) -> None:
        self._root = Path(root).resolve()
        self._root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        target = (self._root / key).resolve()
        # проверка без resolve бессмысленна: 'a/../../etc' формально начинается с 'a'
        if not target.is_relative_to(self._root):
            raise PermissionDenied("путь вне разрешённого каталога")
        return target

    def put(self, key: str, content: bytes, *, content_type: str) -> None:
        """Атомарная запись: временный файл, сброс на диск, переименование."""
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with open(tmp, "wb") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)

    def get(self, key: str) -> bytes:
        path = self._path(key)
        if not path.exists():
            raise NotFound(f"файл {key} не найден")
        return path.read_bytes()

    def open(self, key: str) -> IO[bytes]:
        path = self._path(key)
        if not path.exists():
            raise NotFound(f"файл {key} не найден")
        return open(path, "rb")

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)

    def delete_quietly(self, key: str) -> None:
        try:
            self.delete(key)
        except Exception:  # сбой уборки не должен подменять исходную ошибку
            pass

    def exists(self, key: str) -> bool:
        return self._path(key).exists()

    def list_keys(self, prefix: str) -> Iterator[str]:
        base = self._path(prefix)
        if not base.exists():
            return
        for path in base.rglob("*"):
            if path.is_file() and not path.name.endswith(".tmp"):
                yield str(path.relative_to(self._root)).replace("\\", "/")

    def presigned_url(self, key: str, expires_in: int) -> str | None:
        return None  # локальная реализация временных ссылок не даёт


class S3FileStorage:
    def __init__(
        self,
        endpoint: str,
        bucket: str,
        access_key: str,
        secret_key: str,
        region: str = "ru-central1",
    ) -> None:
        import boto3
        from botocore.config import Config

        self._bucket = bucket
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            region_name=region,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            config=Config(
                retries={"max_attempts": 3, "mode": "standard"},
                connect_timeout=3,
                read_timeout=10,
            ),
        )

    def put(self, key: str, content: bytes, *, content_type: str) -> None:
        from botocore.exceptions import ClientError

        try:
            self._client.put_object(
                Bucket=self._bucket, Key=key, Body=content, ContentType=content_type
            )
        except ClientError as exc:
            raise StorageUnavailable("не удалось сохранить файл") from exc

    def get(self, key: str) -> bytes:
        from botocore.exceptions import ClientError

        try:
            obj = self._client.get_object(Bucket=self._bucket, Key=key)
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in {"NoSuchKey", "404"}:
                raise NotFound(f"файл {key} не найден") from exc
            raise StorageUnavailable("хранилище недоступно") from exc
        return bytes(obj["Body"].read())

    def open(self, key: str) -> IO[bytes]:
        return BytesIO(self.get(key))

    def delete(self, key: str) -> None:
        from botocore.exceptions import ClientError

        try:
            self._client.delete_object(Bucket=self._bucket, Key=key)
        except ClientError as exc:
            raise StorageUnavailable("хранилище недоступно") from exc

    def delete_quietly(self, key: str) -> None:
        try:
            self.delete(key)
        except Exception:
            pass

    def exists(self, key: str) -> bool:
        from botocore.exceptions import ClientError

        try:
            self._client.head_object(Bucket=self._bucket, Key=key)
        except ClientError:
            return False
        return True

    def list_keys(self, prefix: str) -> Iterator[str]:
        paginator = self._client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=self._bucket, Prefix=prefix):
            for item in page.get("Contents", []):
                yield str(item["Key"])

    def presigned_url(self, key: str, expires_in: int) -> str:
        """Временная ссылка: байты передаёт хранилище, а не воркер приложения."""
        return str(
            self._client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self._bucket, "Key": key},
                ExpiresIn=expires_in,
            )
        )


class MemoryFileStorage:
    """Реализация для тестов: быстрая и не оставляет файлов на диске."""

    def __init__(self) -> None:
        self.items: dict[str, tuple[bytes, str]] = {}
        self.fail = False

    def _check(self) -> None:
        if self.fail:
            raise StorageUnavailable("хранилище недоступно")

    def put(self, key: str, content: bytes, *, content_type: str) -> None:
        self._check()
        self.items[key] = (content, content_type)

    def get(self, key: str) -> bytes:
        self._check()
        try:
            return self.items[key][0]
        except KeyError:
            raise NotFound(f"файл {key} не найден") from None

    def open(self, key: str) -> IO[bytes]:
        return BytesIO(self.get(key))

    def delete(self, key: str) -> None:
        self._check()
        self.items.pop(key, None)

    def delete_quietly(self, key: str) -> None:
        self.items.pop(key, None)

    def exists(self, key: str) -> bool:
        return key in self.items

    def list_keys(self, prefix: str) -> Iterator[str]:
        return (k for k in self.items if k.startswith(prefix))

    def presigned_url(self, key: str, expires_in: int) -> str | None:
        return None
