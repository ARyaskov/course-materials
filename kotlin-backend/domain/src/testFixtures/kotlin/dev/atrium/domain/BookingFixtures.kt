package dev.atrium.domain

import java.time.Duration
import java.time.Instant
import kotlin.uuid.Uuid

@DslMarker
annotation class AtriumDsl

@AtriumDsl
class BookingBuilder {
    var id: BookingId = BookingId(Uuid.random())
    var roomId: RoomId = RoomId(Uuid.random())
    var memberId: MemberId = MemberId(Uuid.random())
    var start: Instant = Instant.parse("2026-10-01T10:00:00Z")
    var duration: Duration = Duration.ofHours(1)
    var status: BookingStatus = BookingStatus.Pending(expiresAt = start + Booking.HOLD_TTL)
    var createdAt: Instant = start - Duration.ofDays(1)

    fun slot(start: Instant, duration: Duration = Duration.ofHours(1)) {
        this.start = start
        this.duration = duration
    }

    fun build(): Booking = Booking(
        id = id,
        roomId = roomId,
        memberId = memberId,
        slot = TimeSlot(start, start + duration),
        status = status,
        createdAt = createdAt,
    )
}

fun aBooking(configure: BookingBuilder.() -> Unit = {}): Booking = BookingBuilder().apply(configure).build()

fun aConfirmedBooking(configure: BookingBuilder.() -> Unit = {}): Booking = aBooking {
    status = BookingStatus.Confirmed(PaymentId("pay_test"))
    configure()
}
