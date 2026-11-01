package dev.atrium.infrastructure.postgres

import kotlinx.coroutines.CancellationException
import java.sql.SQLException

/** Повтор транзакции при 40001 (serialization_failure) — блок должен быть идемпотентным и без внешних побочных эффектов. */
suspend fun <T> withSerializationRetry(attempts: Int = 3, block: suspend () -> T): T {
    repeat(attempts - 1) {
        try {
            return block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: SQLException) {
            if (e.sqlState != "40001") throw e
        }
    }
    return block()
}
