"""Сессии обновления токена."""

from datetime import datetime

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from depot.domain.ids import UserId
from depot.domain.models import RefreshSession


class RefreshSessionRepository:
    def __init__(self, session: Session) -> None:
        self._session = session

    def find_by_hash(self, token_hash: str) -> RefreshSession | None:
        stmt = select(RefreshSession).where(RefreshSession.token_hash == token_hash)
        return self._session.scalars(stmt).one_or_none()

    def find_active(self, token_hash: str, now: datetime) -> RefreshSession | None:
        stmt = select(RefreshSession).where(
            RefreshSession.token_hash == token_hash,
            RefreshSession.revoked_at.is_(None),
            RefreshSession.expires_at > now,
        )
        return self._session.scalars(stmt).one_or_none()

    def active_for_user(self, user_id: UserId) -> list[RefreshSession]:
        stmt = (
            select(RefreshSession)
            .where(RefreshSession.user_id == user_id, RefreshSession.revoked_at.is_(None))
            .order_by(RefreshSession.created_at.desc())
        )
        return list(self._session.scalars(stmt).all())

    def store(
        self,
        *,
        user_id: UserId,
        token_hash: str,
        expires_at: datetime,
        user_agent: str | None = None,
        ip: str | None = None,
    ) -> RefreshSession:
        record = RefreshSession(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
            # обрезка по длине колонки: значение приходит от клиента
            user_agent=(user_agent or "")[:255] or None,
            ip=(ip or "")[:45] or None,
        )
        self._session.add(record)
        self._session.flush()
        return record

    def revoke(self, record: RefreshSession, now: datetime) -> None:
        record.revoked_at = now

    def revoke_all_for_user(self, user_id: UserId, now: datetime) -> int:
        """Отзыв всех сессий пользователя.

        Вызывается при обнаружении повторного использования токена обновления:
        отличить сбой сети от кражи невозможно, поэтому выбирается безопасный
        вариант.
        """
        result = self._session.execute(
            update(RefreshSession)
            .where(RefreshSession.user_id == user_id, RefreshSession.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        return result.rowcount

    def delete_expired(self, now: datetime, limit: int) -> int:
        """Уборка просроченных: без неё таблица растёт бесконечно."""
        result = self._session.execute(
            delete(RefreshSession).where(
                RefreshSession.id.in_(
                    select(RefreshSession.id)
                    .where(RefreshSession.expires_at < now)
                    .limit(limit)
                )
            )
        )
        return result.rowcount
