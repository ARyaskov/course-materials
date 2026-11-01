package dev.atrium.infrastructure.events

import dev.atrium.infrastructure.postgres.withConnection
import kotlinx.coroutines.CoroutineDispatcher
import javax.sql.DataSource
import kotlin.uuid.Uuid
import kotlin.uuid.toJavaUuid

/** true — событие новое и помечено; false — уже обрабатывалось этим consumer-ом. Вставка — в транзакции с эффектом. */
class ProcessedEventRepository(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) {
    suspend fun markProcessed(eventId: Uuid, consumer: String): Boolean = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("INSERT INTO processed_events (event_id, consumer) VALUES (?, ?) ON CONFLICT DO NOTHING").use { st ->
            st.setObject(1, eventId.toJavaUuid())
            st.setString(2, consumer)
            st.executeUpdate() == 1
        }
    }
}
