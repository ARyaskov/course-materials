package dev.atrium.infrastructure.outbox

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.EventPublisher
import dev.atrium.infrastructure.events.toDto
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.postgres.withConnection
import kotlinx.coroutines.CoroutineDispatcher
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid

/** Реализация порта EventPublisher: запись в outbox соединением текущей транзакции — атомарно с бронью. */
class OutboxEventPublisher(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) : EventPublisher {

    override suspend fun publish(event: BookingEvent) {
        val dto = event.toDto()
        dataSource.withConnection(dbDispatcher) { connection ->
            connection.prepareStatement(
                "INSERT INTO outbox (event_id, aggregate_id, event_type, payload) VALUES (?, ?, ?, ?::jsonb)",
            ).use { statement ->
                statement.setObject(1, event.eventId.toJavaUuid())
                statement.setObject(2, event.bookingId.value.toJavaUuid())
                statement.setString(3, dto.type())
                statement.setString(4, atriumJsonMapper.writeValueAsString(dto))
                statement.executeUpdate()
            }
        }
    }
}
