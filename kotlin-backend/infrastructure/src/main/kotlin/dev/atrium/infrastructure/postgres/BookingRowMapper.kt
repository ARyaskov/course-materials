package dev.atrium.infrastructure.postgres

import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.PaymentId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import java.sql.ResultSet
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import kotlin.uuid.toKotlinUuid

/**
 * Маппинг строки bookings в доменную модель. Nullability каждой колонки — по схеме V002__bookings.sql:
 * status/room_id/member_id/slot NOT NULL; payment_id, expires_at, cancel_reason, cancelled_at — NULL
 * в зависимости от статуса, инварианты проверяются requireNotNull с текстом для лога.
 */
fun ResultSet.toBooking(): Booking {
    val statusCode: String = getString("status")
    val paymentId: String? = getString("payment_id")
    val expiresAt: Instant? = getObject("expires_at", OffsetDateTime::class.java)?.toInstant()
    val status = when (statusCode) {
        "PENDING" -> BookingStatus.Pending(requireNotNull(expiresAt) { "expires_at is null for PENDING booking" })
        "CONFIRMED" -> BookingStatus.Confirmed(PaymentId(requireNotNull(paymentId) { "payment_id is null for CONFIRMED booking" }))
        "CANCELLED" -> BookingStatus.Cancelled(
            reason = getString("cancel_reason"),
            at = getObject("cancelled_at", OffsetDateTime::class.java).toInstant(),
        )
        "EXPIRED" -> BookingStatus.Expired
        "NO_SHOW" -> BookingStatus.NoShow
        else -> error("Unknown booking status: $statusCode")
    }
    return Booking(
        id = BookingId(getObject("id", UUID::class.java).toKotlinUuid()),
        roomId = RoomId(getObject("room_id", UUID::class.java).toKotlinUuid()),
        memberId = MemberId(getObject("member_id", UUID::class.java).toKotlinUuid()),
        slot = TimeSlot(
            start = getObject("slot_start", OffsetDateTime::class.java).toInstant(),
            end = getObject("slot_end", OffsetDateTime::class.java).toInstant(),
        ),
        status = status,
        createdAt = getObject("created_at", OffsetDateTime::class.java).toInstant(),
        version = getLong("version"),
    )
}

fun BookingStatus.code(): String = when (this) {
    is BookingStatus.Pending -> "PENDING"
    is BookingStatus.Confirmed -> "CONFIRMED"
    is BookingStatus.Cancelled -> "CANCELLED"
    BookingStatus.Expired -> "EXPIRED"
    BookingStatus.NoShow -> "NO_SHOW"
}
