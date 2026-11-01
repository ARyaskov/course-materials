package dev.atrium.application

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingError
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId

/**
 * Один успешный исход — Outcome вместо собственного sealed-типа.
 * Вариант с ранними return выбран вместо flatMap-цепочки: три guard-а читаются сверху вниз,
 * а возврат депозита с побочным эффектом плохо ложится на чистую композицию.
 */
class CancelBooking(
    private val bookings: BookingRepository,
    private val payments: PaymentGateway,
    private val events: EventPublisher,
    private val clock: Clock,
) {
    suspend fun execute(id: BookingId, memberId: MemberId, reason: String): Outcome<Booking, BookingError> {
        val booking = bookings.find(id) ?: return Outcome.Failure(BookingError.BookingNotFound(id))
        if (booking.memberId != memberId) return Outcome.Failure(BookingError.NotOwner(id, memberId))
        if (!booking.isActive) return Outcome.Failure(BookingError.NotCancellable(id, booking.status))

        val status = booking.status
        if (status is BookingStatus.Confirmed) {
            when (val refund = payments.refund(status.paymentId)) {
                is PaymentResult.Refunded -> Unit
                is PaymentResult.Declined -> return Outcome.Failure(BookingError.PaymentDeclined(id, refund.reason))
                is PaymentResult.Unavailable -> return Outcome.Failure(BookingError.PaymentUnavailable(id, "refund unavailable: ${refund.cause}"))
                is PaymentResult.Charged -> error("Unexpected charge result on refund for $id")
            }
        }

        val now = clock.now()
        val cancelled = bookings.save(booking.cancel(reason, now))
        events.publish(BookingEvent.Cancelled(id, reason, now))
        return Outcome.Success(cancelled)
    }
}
