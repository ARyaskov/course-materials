package dev.atrium.domain

/** Ожидаемые отказы операций с бронями. Не исключения: вызывающий код обязан обработать каждый вариант. */
sealed interface BookingError {
    data class RoomNotFound(val roomId: RoomId) : BookingError
    data class BookingNotFound(val bookingId: BookingId) : BookingError
    data class SlotTaken(val roomId: RoomId, val slot: TimeSlot) : BookingError
    data object SlotInPast : BookingError
    data class NotConfirmable(val bookingId: BookingId, val status: BookingStatus) : BookingError
    data class NotCancellable(val bookingId: BookingId, val status: BookingStatus) : BookingError
    data class HoldExpired(val bookingId: BookingId) : BookingError
    data class PaymentDeclined(val bookingId: BookingId, val reason: String) : BookingError
    data class NotOwner(val bookingId: BookingId, val memberId: MemberId) : BookingError
    /** Провайдер платежей не ответил: бронь остаётся Pending, клиенту 503 + Retry-After. */
    data class PaymentUnavailable(val bookingId: BookingId, val cause: String) : BookingError
    data class IdempotencyKeyReuse(val key: String) : BookingError
    data class RequestInProgress(val key: String) : BookingError
}
