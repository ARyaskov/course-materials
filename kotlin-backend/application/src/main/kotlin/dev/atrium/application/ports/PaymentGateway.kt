package dev.atrium.application.ports

import dev.atrium.domain.BookingId
import dev.atrium.domain.Money
import dev.atrium.domain.PaymentId

/** Внешний платёжный провайдер PayGate: списание депозита и возврат. */
interface PaymentGateway {
    suspend fun charge(bookingId: BookingId, amount: Money, idempotencyKey: String): PaymentResult
    suspend fun refund(paymentId: PaymentId): PaymentResult
}

sealed interface PaymentResult {
    data class Charged(val paymentId: PaymentId) : PaymentResult
    data class Refunded(val paymentId: PaymentId) : PaymentResult
    data class Declined(val reason: String) : PaymentResult
    /** Провайдер недоступен или не ответил вовремя — операцию можно повторить. */
    data class Unavailable(val cause: String) : PaymentResult
}
