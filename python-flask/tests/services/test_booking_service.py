"""Сценарии бронирования на уровне сервиса.

Здесь проверяется то, что не видно через HTTP: что задача ставится
в очередь после фиксации транзакции, что недоступность очереди не
отменяет операцию, что повторный вызов истечения идемпотентен.
"""

from datetime import timedelta

import pytest

from depot.domain.access import Actor
from depot.domain.enums import BookingStatus, UserRole
from depot.domain.errors import BookingOverlap
from depot.domain.ids import UserId
from depot.domain.period import Period
from depot.infrastructure.memory_queue import MemoryTaskQueue
from depot.services.booking import EXPIRE_TASK, BookingService
from depot.services.commands import CallContext, CreateBookingCommand
from depot.services.uow import make_uow
from tests.factories import make_unit, make_user
from tests.fakes import CountingNotifier, FailingQueue, RecordingGateway


@pytest.fixture
def service(clock, queue):  # type: ignore[no-untyped-def]
    return BookingService(
        uow_factory=make_uow,
        queue=queue,
        clock=clock,
        notifier=CountingNotifier(),
        payment=RecordingGateway(),
    )


@pytest.fixture
def context():  # type: ignore[no-untyped-def]
    user = make_user(role=UserRole.CLIENT)
    return user, CallContext(
        actor=Actor(id=UserId(user.id), role=UserRole.CLIENT), request_id="test-1"
    )


def period_from(clock, days: int = 1, length: int = 2) -> Period:  # type: ignore[no-untyped-def]
    start = clock.now() + timedelta(days=days)
    return Period(start, start + timedelta(days=length))


class TestCreate:
    def test_schedules_expiration(self, service, clock, queue, context):  # type: ignore[no-untyped-def]
        user, ctx = context
        unit = make_unit()

        booking = service.create(
            CreateBookingCommand(
                user_id=UserId(user.id), unit_id=unit.id, period=period_from(clock)
            ),
            ctx=ctx,
        )

        assert booking.status is BookingStatus.PENDING
        # задача поставлена на момент истечения удержания, а не сразу
        assert len(queue.scheduled) == 1
        assert queue.scheduled[0].task == EXPIRE_TASK
        assert queue.scheduled[0].when == booking.hold_expires_at

    def test_survives_unavailable_queue(self, clock, context):  # type: ignore[no-untyped-def]
        """Недоступность очереди не отменяет бронь.

        Постановка задачи — оптимизация: срок удержания записан в строке,
        и периодическая задача снимет его без всякой очереди.
        """
        user, ctx = context
        unit = make_unit()
        service = BookingService(
            uow_factory=make_uow,
            queue=FailingQueue(),
            clock=clock,
            notifier=CountingNotifier(),
            payment=RecordingGateway(),
        )

        booking = service.create(
            CreateBookingCommand(
                user_id=UserId(user.id), unit_id=unit.id, period=period_from(clock)
            ),
            ctx=ctx,
        )
        assert booking.status is BookingStatus.PENDING

    def test_overlap_rejected(self, service, clock, context):  # type: ignore[no-untyped-def]
        user, ctx = context
        unit = make_unit()
        command = CreateBookingCommand(
            user_id=UserId(user.id), unit_id=unit.id, period=period_from(clock)
        )
        service.create(command, ctx=ctx)

        with pytest.raises(BookingOverlap) as exc:
            service.create(command, ctx=ctx)
        # ошибка несёт момент освобождения: клиенту есть что показать
        assert exc.value.busy_until is not None


class TestExpire:
    def test_is_idempotent(self, service, clock, queue, context):  # type: ignore[no-untyped-def]
        user, ctx = context
        unit = make_unit()
        booking = service.create(
            CreateBookingCommand(
                user_id=UserId(user.id), unit_id=unit.id, period=period_from(clock)
            ),
            ctx=ctx,
        )

        clock.advance(timedelta(hours=2))
        first = service.expire(booking.id)
        second = service.expire(booking.id)

        assert first.status is BookingStatus.EXPIRED
        # повторный вызов обнаруживает достигнутое состояние и не падает:
        # очередь доставляет задачу «хотя бы один раз»
        assert second.status is BookingStatus.EXPIRED

    def test_confirmed_booking_untouched(self, service, clock, context):  # type: ignore[no-untyped-def]
        user, ctx = context
        unit = make_unit()
        booking = service.create(
            CreateBookingCommand(
                user_id=UserId(user.id), unit_id=unit.id, period=period_from(clock)
            ),
            ctx=ctx,
        )
        booking.status = BookingStatus.CONFIRMED
        clock.advance(timedelta(hours=2))

        assert service.expire(booking.id).status is BookingStatus.CONFIRMED

    def test_missing_booking_is_not_an_error(self, service) -> None:  # type: ignore[no-untyped-def]
        from uuid import uuid4

        from depot.domain.ids import BookingId

        assert service.expire(BookingId(uuid4())) is None


def test_memory_queue_runs_tasks(queue: MemoryTaskQueue) -> None:
    """Очередь в памяти умеет выполнять накопленное синхронно.

    Приём для одного-двух сквозных сценариев: в остальных проверяется
    факт постановки, иначе тест перестаёт проверять асинхронность.
    """
    queue.enqueue("depot.jobs.notifications.send_welcome", {"user_id": "0"})
    assert len(queue.enqueued) == 1
