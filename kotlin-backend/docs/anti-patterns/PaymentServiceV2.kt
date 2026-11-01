// Маятник в другую сторону — DSL и Either раньше, чем команда готова (урок 16.4). Учебный образец.
package paygate.v2

import arrow.core.Either
import arrow.core.left
import arrow.core.right

sealed interface Failure { data class NotFound(val id: String) : Failure; data class Declined(val reason: String) : Failure }

class ChargeSpec { var bookingId: String = ""; var amount: Long = 0; var currency: String = "RUB"; var retries: Int = 3 }
fun charge(block: ChargeSpec.() -> Unit): ChargeSpec = ChargeSpec().apply(block)

class PaymentService(private val gateway: Gateway) {
    suspend fun charge(spec: ChargeSpec): Either<Failure, Charge> =
        gateway.charge(spec.bookingId, spec.amount).fold({ Failure.Declined(it).left() }, { it.right() })
}

interface Gateway { suspend fun charge(bookingId: String, amount: Long): Either<String, Charge> }
data class Charge(val id: String, val amount: Long)

// Использование: service.charge(charge { bookingId = "b1"; amount = 1500 }).fold({ ... }, { ... })
// Тот же результат в Atrium: sealed PaymentResult + именованные аргументы, без DSL и Either.
