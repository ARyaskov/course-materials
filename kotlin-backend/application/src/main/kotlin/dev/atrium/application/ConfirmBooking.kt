package dev.atrium.application

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.Metrics
import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.ports.SpanScope
import dev.atrium.application.ports.Tracing
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingError
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import io.github.oshai.kotlinlogging.KotlinLogging
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

sealed interface ConfirmResult {
    data class Confirmed(val booking: Booking) : ConfirmResult
    data class AlreadyConfirmed(val booking: Booking) : ConfirmResult
    data class Rejected(val error: BookingError) : ConfirmResult
}

private val log = KotlinLogging.logger {}

class ConfirmBooking(
    private val bookings: BookingRepository,
    private val rooms: RoomRepository,
    private val payments: PaymentGateway,
    private val events: EventPublisher,
    private val clock: Clock,
    private val metrics: Metrics = Metrics.None,
    private val tracing: Tracing = Tracing.None,
) {
    /** Span на весь use case, timer вокруг PayGate, counter-ы по исходу (уроки 14.2, 14.3). */
    suspend fun execute(id: BookingId, memberId: MemberId): ConfirmResult =
        tracing.span("usecase.confirm_booking", mapOf("booking.id" to id.value)) {
            metrics.timed("atrium.bookings.confirm.duration") { confirm(id, memberId) }
                .also { result -> if (result is ConfirmResult.Rejected) metrics.count("atrium.bookings.confirm.rejected", "reason" to result.error::class.simpleName!!) }
        }

    private suspend fun SpanScope.confirm(id: BookingId, memberId: MemberId): ConfirmResult {
        val booking = bookings.find(id) ?: return ConfirmResult.Rejected(BookingError.BookingNotFound(id))
        if (booking.memberId != memberId) return ConfirmResult.Rejected(BookingError.NotOwner(id, memberId))
        val now = clock.now()

        return when (val status = booking.status) {
            is BookingStatus.Pending if status.expiresAt < now ->
                ConfirmResult.Rejected(BookingError.HoldExpired(id))
            is BookingStatus.Pending -> {
                val room = rooms.find(booking.roomId)
                    ?: return ConfirmResult.Rejected(BookingError.RoomNotFound(booking.roomId))
                currentCoroutineContext().ensureActive() // клиент уже отключился — не списывать депозит
                val payment = metrics.timed("atrium.paygate.calls", "operation" to "charge") {
                    withTimeoutOrNull(PAYMENT_TIMEOUT) {
                        payments.charge(id, room.depositFor(booking.slot), idempotencyKey = "confirm:${id.value}")
                    } ?: PaymentResult.Unavailable("PayGate timed out after $PAYMENT_TIMEOUT")
                }
                when (payment) {
                    is PaymentResult.Charged -> withContext(NonCancellable) {
                        // Депозит списан — фиксация не должна быть отменена обрывом клиента
                        val confirmed = bookings.save(booking.confirm(payment.paymentId))
                        events.publish(BookingEvent.Confirmed(id, now))
                        metrics.count("atrium.bookings.confirmed")
                        log.atInfo {
                            message = "booking.confirmed"
                            payload = mapOf("bookingId" to id.value.toString(), "paymentId" to payment.paymentId.value)
                        }
                        ConfirmResult.Confirmed(confirmed)
                    }
                    is PaymentResult.Declined -> {
                        event("payment.declined", mapOf("reason" to payment.reason))
                        log.atWarn { message = "payment.declined"; payload = mapOf("bookingId" to id.value.toString(), "reason" to payment.reason) }
                        ConfirmResult.Rejected(BookingError.PaymentDeclined(id, payment.reason))
                    }
                    is PaymentResult.Unavailable -> withContext(NonCancellable) {
                        // Fallback: холд продлевается, клиент повторит позже (503 + Retry-After)
                        bookings.save(booking.extendHold(now + HOLD_EXTENSION))
                        ConfirmResult.Rejected(BookingError.PaymentUnavailable(id, payment.cause))
                    }
                    is PaymentResult.Refunded -> error("Unexpected refund result on charge for $id")
                }
            }
            is BookingStatus.Confirmed -> ConfirmResult.AlreadyConfirmed(booking)
            is BookingStatus.Cancelled, BookingStatus.Expired, BookingStatus.NoShow ->
                ConfirmResult.Rejected(BookingError.NotConfirmable(id, status))
        }
    }

    private companion object {
        val PAYMENT_TIMEOUT = 8.seconds // внешний бюджет: 2 попытки × 5 с внутри ResilientPaymentGateway не должны его превысить
        val HOLD_EXTENSION: java.time.Duration = java.time.Duration.ofMinutes(10)
    }
}
