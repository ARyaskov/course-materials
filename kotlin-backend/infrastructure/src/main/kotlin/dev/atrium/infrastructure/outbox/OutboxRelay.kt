package dev.atrium.infrastructure.outbox

import dev.atrium.infrastructure.events.BookingEventDto
import dev.atrium.infrastructure.events.BookingEventSender
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.json.read
import dev.atrium.infrastructure.postgres.JobLease
import dev.atrium.infrastructure.postgres.withConnection
import io.micrometer.core.instrument.MeterRegistry
import kotlinx.coroutines.CoroutineDispatcher
import java.sql.ResultSet
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.util.concurrent.atomic.AtomicLong
import javax.sql.DataSource

private data class OutboxRow(val id: Long, val payload: String, val createdAt: Instant)

/** Один активный relay на все инстансы (JobLease): порядок событий по агрегату сохраняется. */
class OutboxRelay(
    private val dataSource: DataSource,
    private val dbDispatcher: CoroutineDispatcher,
    private val sender: BookingEventSender,
    private val lease: JobLease,
    private val batchSize: Int = 200,
    registry: MeterRegistry,
) {
    private val lag: AtomicLong = registry.gauge("atrium.outbox.lag_seconds", AtomicLong(0))
    private val published = registry.counter("atrium.outbox.published")

    /** Один проход: взять батч неопубликованных, отправить по порядку, пометить. Возвращает число опубликованных. */
    suspend fun relayOnce(): Int = lease.tryRun("outbox-relay") {
        val batch = dataSource.withConnection(dbDispatcher) { connection ->
            connection.prepareStatement(
                "SELECT id, event_id, aggregate_id, payload, created_at FROM outbox WHERE published_at IS NULL ORDER BY id LIMIT ? FOR UPDATE SKIP LOCKED",
            ).use { st ->
                st.setInt(1, batchSize)
                st.executeQuery().use { rs -> buildList { while (rs.next()) add(rs.toOutboxRow()) } }
            }
        }
        if (batch.isEmpty()) return@tryRun 0
        lag.set(Duration.between(batch.first().createdAt, Instant.now()).seconds)

        for (row in batch) {
            sender.send(atriumJsonMapper.read<BookingEventDto>(row.payload)) // acks=all: успех означает запись в брокер
            dataSource.withConnection(dbDispatcher) { connection ->
                connection.prepareStatement("UPDATE outbox SET published_at = now() WHERE id = ?").use { st ->
                    st.setLong(1, row.id)
                    st.executeUpdate()
                }
            }
            published.increment()
        }
        batch.size
    } ?: 0

    private fun ResultSet.toOutboxRow() = OutboxRow(getLong("id"), getString("payload"), getObject("created_at", OffsetDateTime::class.java).toInstant())
}
