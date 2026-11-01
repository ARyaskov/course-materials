package dev.atrium.domain

import java.time.Duration
import java.time.Instant

sealed interface BookingStatus {
    data class Pending(val expiresAt: Instant) : BookingStatus
    data class Confirmed(val paymentId: PaymentId) : BookingStatus
    data class Cancelled(val reason: String, val at: Instant) : BookingStatus
    data object Expired : BookingStatus
    data object NoShow : BookingStatus
}

/**
 * Бронь неизменяема: каждый переход возвращает новый экземпляр.
 * Переходы, невозможные по правилам домена, — ошибка программиста (IllegalStateException),
 * потому что вызывающий код обязан проверить статус заранее (см. BookingError в use case).
 */
@MustUseReturnValues
data class Booking(
    val id: BookingId,
    val roomId: RoomId,
    val memberId: MemberId,
    val slot: TimeSlot,
    val status: BookingStatus,
    val createdAt: Instant,
    val version: Long = 0,
) {
    val isActive: Boolean
        get() = when (status) {
            is BookingStatus.Pending, is BookingStatus.Confirmed -> true
            is BookingStatus.Cancelled, BookingStatus.Expired, BookingStatus.NoShow -> false
        }

    fun confirm(paymentId: PaymentId): Booking {
        check(status is BookingStatus.Pending) { "Only pending booking can be confirmed, was $status" }
        return copy(status = BookingStatus.Confirmed(paymentId))
    }

    fun cancel(reason: String, at: Instant): Booking {
        check(isActive) { "Only active booking can be cancelled, was $status" }
        return copy(status = BookingStatus.Cancelled(reason, at))
    }

    /** Fallback при недоступном провайдере: холд продлевается, бронь остаётся Pending. */
    fun extendHold(until: Instant): Booking {
        check(status is BookingStatus.Pending) { "Only pending booking can extend hold, was $status" }
        return copy(status = BookingStatus.Pending(expiresAt = until))
    }

    fun expire(): Booking {
        check(status is BookingStatus.Pending) { "Only pending booking can expire, was $status" }
        return copy(status = BookingStatus.Expired)
    }

    fun markNoShow(): Booking {
        check(status is BookingStatus.Confirmed) { "Only confirmed booking can be no-show, was $status" }
        return copy(status = BookingStatus.NoShow)
    }

    companion object {
        val HOLD_TTL: Duration = Duration.ofMinutes(15)
        val NO_SHOW_GRACE: Duration = Duration.ofMinutes(15)

        fun create(id: BookingId, room: Room, memberId: MemberId, slot: TimeSlot, now: Instant): Booking {
            require(slot.start >= now) { "Cannot book a slot in the past: ${slot.start} < $now" }
            return Booking(
                id = id,
                roomId = room.id,
                memberId = memberId,
                slot = slot,
                status = BookingStatus.Pending(expiresAt = now + HOLD_TTL),
                createdAt = now,
            )
        }
    }
}
