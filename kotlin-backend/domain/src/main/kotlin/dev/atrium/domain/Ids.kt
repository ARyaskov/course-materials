package dev.atrium.domain

import kotlin.uuid.Uuid

@JvmInline value class LocationId(val value: Uuid)
@JvmInline value class RoomId(val value: Uuid) {
    companion object {
        fun parse(raw: String): RoomId? = Uuid.parseOrNull(raw)?.let(::RoomId)
    }
}
@JvmInline value class BookingId(val value: Uuid) {
    companion object {
        fun parse(raw: String): BookingId? = Uuid.parseOrNull(raw)?.let(::BookingId)
    }
}
@JvmInline value class MemberId(val value: Uuid)

/** Идентификатор платежа от внешнего провайдера PayGate: непустая строка ограниченной длины. */
@JvmInline
value class PaymentId(val value: String) {
    init {
        require(value.isNotBlank() && value.length <= 64) { "PaymentId must be 1..64 non-blank chars" }
    }
}
