"""Общие приспособления тестов.

Область видимости выбрана намеренно. Приложение и подключение к базе —
на сессию: их создание дорого. Транзакция — на тест: она откатывается,
и следующий тест видит чистую базу без пересоздания таблиц.

Порядок тестов при этом перестаёт иметь значение, а это единственное,
что отличает набор тестов от набора совпадений.
"""

from collections.abc import Iterator
from datetime import UTC, datetime

import pytest
from flask import Flask
from sqlalchemy import event

from depot import create_app
from depot.extensions import db


@pytest.fixture(scope="session")
def app() -> Iterator[Flask]:
    application = create_app("testing")
    with application.app_context():
        db.create_all()
        yield application
        db.session.remove()
        db.drop_all()


@pytest.fixture(autouse=True)
def session(app: Flask) -> Iterator[None]:
    """Транзакция на тест с откатом в конце.

    Вложенная транзакция и её восстановление после каждого commit позволяют
    тестировать код, который сам вызывает commit: внешняя транзакция всё
    равно откатится.
    """
    connection = db.engine.connect()
    transaction = connection.begin()

    db.session.configure(bind=connection, join_transaction_mode="create_savepoint")
    nested = connection.begin_nested()

    @event.listens_for(db.session, "after_transaction_end")
    def restart_savepoint(sess, trans):  # type: ignore[no-untyped-def]
        nonlocal nested
        if not nested.is_active:
            nested = connection.begin_nested()

    yield

    event.remove(db.session, "after_transaction_end", restart_savepoint)
    db.session.remove()
    transaction.rollback()
    connection.close()


@pytest.fixture
def client(app: Flask):  # type: ignore[no-untyped-def]
    return app.test_client()


@pytest.fixture
def clock(app: Flask):  # type: ignore[no-untyped-def]
    """Фиксированные часы вместо системных.

    Тест на просрочку не ждёт сутки: он сдвигает время.
    """
    from depot.infrastructure.clock import FixedClock

    fixed = FixedClock(datetime(2026, 3, 1, 12, 0, tzinfo=UTC))
    app.extensions["clock"] = fixed
    return fixed


@pytest.fixture
def queue(app: Flask):  # type: ignore[no-untyped-def]
    from depot.infrastructure.memory_queue import MemoryTaskQueue

    memory = MemoryTaskQueue()
    app.extensions["queue"] = memory
    return memory


@pytest.fixture
def notifier(app: Flask):  # type: ignore[no-untyped-def]
    from depot.infrastructure.notifier import MemoryNotifier

    memory = MemoryNotifier()
    app.extensions["notifier"] = memory
    return memory


@pytest.fixture
def auth_headers(app: Flask):  # type: ignore[no-untyped-def]
    """Фабрика заголовков авторизации.

    Возвращается функция, а не готовый заголовок: тесту доступа нужны
    несколько разных ролей в одном сценарии.
    """

    def make(user) -> dict[str, str]:  # type: ignore[no-untyped-def]
        token = app.extensions["tokens"].issue_access(user)
        return {"Authorization": f"Bearer {token.value}"}

    return make
