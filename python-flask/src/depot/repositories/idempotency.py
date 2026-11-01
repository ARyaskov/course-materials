"""Ключи идемпотентности.

Запись создаётся в той же транзакции, что и операция. Первичный ключ по ключу
идемпотентности даёт гарантию при параллельном повторе: вставить вторую запись
не получится.
"""

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from depot.domain.errors import IdempotencyKeyReused
from depot.domain.ids import UserId
from depot.domain.models import IdempotencyRecord

RECORD_TTL = timedelta(hours=24)


class IdempotencyRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def find(self, key: str, user_id: UserId) -> IdempotencyRecord | None:
        stmt = select(IdempotencyRecord).where(
            IdempotencyRecord.key == key, IdempotencyRecord.user_id == user_id
        )
        return self._session.scalars(stmt).one_or_none()

    def replay_or_none(
        self, key: str, user_id: UserId, request_hash: str
    ) -> tuple[dict[str, Any], int] | None:
        """Сохранённый ответ для повторного запроса.

        Несовпадение отпечатка тела означает, что тот же ключ использован
        с другими данными: это не повтор, а конфликт.
        """
        record = self.find(key, user_id)
        if record is None:
            return None
        if record.request_hash != request_hash:
            raise IdempotencyKeyReused("ключ идемпотентности использован с другими данными")
        return record.response_body, record.status_code

    def store(
        self,
        *,
        key: str,
        user_id: UserId,
        request_hash: str,
        response_body: dict[str, Any],
        status_code: int,
    ) -> None:
        record = IdempotencyRecord(
            key=key,
            user_id=user_id,
            request_hash=request_hash,
            response_body=response_body,
            status_code=status_code,
        )
        self._session.add(record)
        try:
            self._session.flush()
        except IntegrityError as exc:
            raise IdempotencyKeyReused("ключ идемпотентности уже использован") from exc

    def delete_expired(self, now: datetime, limit: int) -> int:
        cutoff = now - RECORD_TTL
        result = self._session.execute(
            delete(IdempotencyRecord).where(
                IdempotencyRecord.key.in_(
                    select(IdempotencyRecord.key)
                    .where(IdempotencyRecord.created_at < cutoff)
                    .limit(limit)
                )
            )
        )
        return result.rowcount
