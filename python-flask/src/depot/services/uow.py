"""Единица работы.

Объединяет репозитории общей транзакцией и даёт сервису одну точку управления
границами. Границы транзакции совпадают с границами операции домена: либо бронь
подтверждена и счёт создан, либо ничего не изменилось.

Репозитории при этом не вызывают ни `commit`, ни `rollback`.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from types import TracebackType

from sqlalchemy.orm import Session

from depot.extensions import db
from depot.repositories.booking import BookingRepository
from depot.repositories.catalog import CatalogRepository, StationRepository, UnitRepository
from depot.repositories.idempotency import IdempotencyRepository
from depot.repositories.invoice import InvoiceRepository
from depot.repositories.rental import RentalRepository
from depot.repositories.session import RefreshSessionRepository
from depot.repositories.user import UserRepository


class UnitOfWork:
    def __init__(self, session: Session) -> None:
        self._session = session
        self.bookings = BookingRepository(session)
        self.rentals = RentalRepository(session)
        self.invoices = InvoiceRepository(session)
        self.units = UnitRepository(session)
        self.catalog = CatalogRepository(session)
        self.stations = StationRepository(session)
        self.users = UserRepository(session)
        self.sessions = RefreshSessionRepository(session)
        self.idempotency = IdempotencyRepository(session)

    @property
    def session(self) -> Session:
        return self._session

    def __enter__(self) -> "UnitOfWork":
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        # Возврат None, а не True: исключение должно распространяться дальше.
        # Иначе клиент получил бы 200 при неудачной операции.
        if exc_type is None:
            self._session.commit()
        else:
            self._session.rollback()

    def flush(self) -> None:
        self._session.flush()


def make_uow() -> UnitOfWork:
    """Фабрика для сервисов.

    Сервис получает фабрику, а не готовый объект: каждая операция открывает
    свою транзакцию.
    """
    return UnitOfWork(db.session)


@contextmanager
def session_scope() -> Iterator[Session]:
    """Транзакция без репозиториев — для задач и скриптов."""
    session = db.session
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
