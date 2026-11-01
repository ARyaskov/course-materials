package dev.atrium.infrastructure.postgres

import dev.atrium.application.ports.Transaction
import dev.atrium.application.ports.TransactionRunner
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.withContext
import java.sql.Connection
import javax.sql.DataSource
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/**
 * Транзакция привязана к корутине, а не к потоку: соединение лежит в CoroutineContext,
 * и репозитории достают его через currentTransaction(). withContext внутри блока безопасен.
 */
class JdbcTransaction(val connection: Connection) : Transaction, AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<JdbcTransaction>
}

class JdbcTransactionRunner(
    private val dataSource: DataSource,
    private val dbDispatcher: CoroutineDispatcher,
) : TransactionRunner {

    override suspend fun <T> inTransaction(block: suspend context(Transaction) () -> T): T {
        // Вложенный вызов присоединяется к открытой транзакции (аналог REQUIRED)
        currentCoroutineContext()[JdbcTransaction]?.let { tx -> return context(tx) { block() } }

        return withContext(dbDispatcher) {
            dataSource.connection.use { connection ->
                connection.autoCommit = false
                val tx = JdbcTransaction(connection)
                try {
                    val result = withContext(tx) { context(tx) { block() } }
                    connection.commit()
                    result
                } catch (e: Throwable) {
                    connection.rollback()
                    throw e
                }
            }
        }
    }
}

/** Соединение текущей транзакции или null — репозиторий тогда берёт соединение из пула сам. */
suspend fun currentTransaction(): JdbcTransaction? = currentCoroutineContext()[JdbcTransaction]

/** Выполнить блок на соединении транзакции, если она открыта, иначе — на новом соединении с autoCommit. */
suspend inline fun <T> DataSource.withConnection(dbDispatcher: CoroutineDispatcher, crossinline block: (Connection) -> T): T {
    val tx = currentTransaction()
    return if (tx != null) {
        withContext(dbDispatcher) { block(tx.connection) }
    } else {
        withContext(dbDispatcher) { connection.use { block(it) } }
    }
}
