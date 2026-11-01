package dev.atrium.infrastructure.postgres

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import javax.sql.DataSource

/** Лизинг задачи через session-level advisory lock: пока соединение держит блокировку, другие инстансы пропускают запуск. */
class JobLease(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) {

    suspend fun <T> tryRun(jobName: String, block: suspend () -> T): T? = withContext(dbDispatcher) {
        dataSource.connection.use { connection ->
            val acquired = connection.prepareStatement("SELECT pg_try_advisory_lock(hashtext(?))").use { st ->
                st.setString(1, jobName)
                st.executeQuery().use { rs -> rs.next() && rs.getBoolean(1) }
            }
            if (!acquired) return@withContext null
            try {
                block()
            } finally {
                connection.prepareStatement("SELECT pg_advisory_unlock(hashtext(?))").use { st ->
                    st.setString(1, jobName)
                    st.execute()
                }
            }
        }
    }
}
