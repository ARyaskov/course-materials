package dev.atrium.infrastructure.events

import dev.atrium.application.ports.Notification
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.postgres.withConnection
import kotlinx.coroutines.CoroutineDispatcher
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid

/** Эффект consumer-а — запись; id = eventId, поэтому UNIQUE даёт второй слой дедупликации. */
class NotificationOutboxRepository(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) {
    suspend fun enqueue(notification: Notification): Boolean = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement(
            "INSERT INTO notification_outbox (id, member_id, booking_id, template, params) VALUES (?, ?, ?, ?, ?::jsonb) ON CONFLICT DO NOTHING",
        ).use { st ->
            st.setObject(1, notification.id.toJavaUuid())
            st.setObject(2, notification.memberId.value.toJavaUuid())
            st.setObject(3, notification.bookingId.value.toJavaUuid())
            st.setString(4, notification.template)
            st.setString(5, atriumJsonMapper.writeValueAsString(notification.params))
            st.executeUpdate() == 1
        }
    }
}
