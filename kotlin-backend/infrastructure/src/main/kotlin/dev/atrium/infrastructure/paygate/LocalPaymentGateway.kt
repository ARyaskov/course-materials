package dev.atrium.infrastructure.paygate

import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.domain.BookingId
import dev.atrium.domain.Money
import dev.atrium.domain.PaymentId
import kotlin.uuid.Uuid

/** Заглушка провайдера для профиля local: всегда списывает и возвращает. Не для тестов — там FakePaymentGateway. */
class LocalPaymentGateway : PaymentGateway {
    override suspend fun charge(bookingId: BookingId, amount: Money, idempotencyKey: String): PaymentResult =
        PaymentResult.Charged(PaymentId("local_${Uuid.random()}"))

    override suspend fun refund(paymentId: PaymentId): PaymentResult = PaymentResult.Refunded(paymentId)
}
