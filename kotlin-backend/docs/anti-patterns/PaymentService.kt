// «Java на Kotlin» — первая версия PayGate (урок 16.4). Не компилируется в проекте, учебный образец.
package paygate.legacy

import java.util.Optional
import java.util.stream.Collectors

class Charge {
    var id: String? = null
    var status: String? = null
    var amount: Long? = null
    fun getStatusOrNull(): String? = status
}

object ChargeUtils {
    @JvmStatic fun isActive(c: Charge): Boolean = c.status != null && c.status.equals("ACTIVE")
}

class PaymentService(private val repository: ChargeRepository) {
    suspend fun findActive(bookingId: String): Optional<Charge> {
        val charges = repository.findByBooking(bookingId)
        return charges.stream()
            .filter { c -> c.status != null && c.status.equals("ACTIVE") }
            .findFirst()
    }

    suspend fun formatAmount(c: Charge): String = String.format("%.2f", c.amount!! / 100.0)

    fun charge(bookingId: String, amount: Long): Charge {
        try {
            val c = Charge()
            c.id = java.util.UUID.randomUUID().toString()
            c.amount = amount
            c.status = "ACTIVE"
            return repository.save(c)
        } catch (e: Exception) {
            throw RuntimeException(e)
        }
    }
}

interface ChargeRepository {
    fun findByBooking(bookingId: String): List<Charge>
    fun save(c: Charge): Charge
}
