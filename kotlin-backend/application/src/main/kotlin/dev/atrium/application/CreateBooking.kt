package dev.atrium.application

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.IdGenerator
import dev.atrium.application.ports.IdempotencyKey
import dev.atrium.application.ports.IdempotencyOutcome
import dev.atrium.application.ports.IdempotencyStore
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.ports.SlotConflictException
import dev.atrium.application.ports.TransactionRunner
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingError
import dev.atrium.domain.MemberId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot

data class CreateBookingCommand(
    val roomId: RoomId,
    val memberId: MemberId,
    val slot: TimeSlot,
    val comment: String? = null,
)

sealed interface CreateResult {
    data class Created(val booking: Booking) : CreateResult
    /** Повтор с тем же Idempotency-Key: та же бронь в актуальном состоянии. */
    data class Replayed(val booking: Booking) : CreateResult
    data class Rejected(val error: BookingError) : CreateResult
}

class CreateBooking(
    private val bookings: BookingRepository,
    private val rooms: RoomRepository,
    private val events: EventPublisher,
    private val ids: IdGenerator,
    private val clock: Clock,
    private val transactions: TransactionRunner = TransactionRunner.NONE,
    private val idempotency: IdempotencyStore? = null,
) {
    /** Чтение пересечений и вставка — одна транзакция; гонку между ними ловит exclusion constraint. */
    suspend fun execute(command: CreateBookingCommand, key: IdempotencyKey? = null): CreateResult {
        if (key == null || idempotency == null) return guarded { transactions.transactional { create(command) } }
        return when (val outcome = idempotency.begin(command.memberId, key.key, key.requestHash)) {
            is IdempotencyOutcome.Replay -> bookings.find(outcome.bookingId)?.let { CreateResult.Replayed(it) }
                ?: CreateResult.Rejected(BookingError.BookingNotFound(outcome.bookingId))
            IdempotencyOutcome.Mismatch -> CreateResult.Rejected(BookingError.IdempotencyKeyReuse(key.key))
            IdempotencyOutcome.InProgress -> CreateResult.Rejected(BookingError.RequestInProgress(key.key))
            IdempotencyOutcome.Acquired -> guarded {
                transactions.transactional {
                    create(command).also { result ->
                        if (result is CreateResult.Created) idempotency.complete(command.memberId, key.key, result.booking.id, 201)
                    }
                }
            }
        }
    }

    private suspend fun guarded(block: suspend () -> CreateResult): CreateResult = try {
        block()
    } catch (e: SlotConflictException) {
        CreateResult.Rejected(BookingError.SlotTaken(e.roomId, e.slot))
    }

    private suspend fun create(command: CreateBookingCommand): CreateResult {
        val now = clock.now()
        if (command.slot.start < now) return CreateResult.Rejected(BookingError.SlotInPast)
        val room = rooms.find(command.roomId) ?: return CreateResult.Rejected(BookingError.RoomNotFound(command.roomId))

        val overlapping = bookings.findActiveByRoom(room.id, command.slot.start, command.slot.end)
        if (overlapping.any { it.slot overlaps command.slot }) {
            return CreateResult.Rejected(BookingError.SlotTaken(room.id, command.slot))
        }

        val booking = Booking.create(ids.nextBookingId(), room, command.memberId, command.slot, now)
        val saved = bookings.save(booking) // exclusion constraint в БД — последняя линия защиты от гонки
        events.publish(BookingEvent.Created(saved.id, saved.roomId, saved.memberId, saved.slot, now))
        return CreateResult.Created(saved)
    }
}
