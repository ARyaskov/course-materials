package dev.atrium.infrastructure.postgres

import dev.atrium.application.ports.BackfillCheckpoint
import dev.atrium.application.ports.BackfillCheckpointRepository
import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.UtilizationDelta
import dev.atrium.application.ports.UtilizationRepository
import dev.atrium.domain.BookingId
import kotlinx.coroutines.CoroutineDispatcher
import java.sql.Date
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

/** Приращение по дельтам; идемпотентность — через транзакцию с checkpoint-ом backfill-а или дедупликацию событий. */
class JdbcUtilizationRepository(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) : UtilizationRepository {
    override suspend fun upsertAll(deltas: List<UtilizationDelta>) = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement(
            """
            INSERT INTO room_utilization (room_id, day, minutes_booked, updated_at) VALUES (?, ?, ?, now())
            ON CONFLICT (room_id, day) DO UPDATE SET minutes_booked = room_utilization.minutes_booked + EXCLUDED.minutes_booked, updated_at = now()
            """.trimIndent(),
        ).use { st ->
            for (delta in deltas) {
                st.setObject(1, delta.roomId.value.toJavaUuid())
                st.setDate(2, Date.valueOf(delta.day))
                st.setLong(3, delta.minutesBooked)
                st.addBatch()
            }
            st.executeBatch()
        }
        Unit
    }
}

class JdbcBackfillCheckpointRepository(private val dataSource: DataSource, private val dbDispatcher: CoroutineDispatcher) : BackfillCheckpointRepository {
    override suspend fun find(runId: String): BackfillCheckpoint? = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("SELECT cursor_at, cursor_id, processed, completed_at FROM backfill_runs WHERE run_id = ?").use { st ->
            st.setString(1, runId)
            st.executeQuery().use { rs ->
                if (!rs.next()) return@withConnection null
                val cursorAt = rs.getObject("cursor_at", OffsetDateTime::class.java)?.toInstant()
                val cursorId = rs.getObject("cursor_id", UUID::class.java)
                BackfillCheckpoint(
                    runId = runId,
                    cursor = if (cursorAt != null && cursorId != null) BookingCursor(cursorAt, BookingId(cursorId.toKotlinUuid())) else null,
                    processed = rs.getLong("processed"),
                    completedAt = rs.getObject("completed_at", OffsetDateTime::class.java)?.toInstant(),
                )
            }
        }
    }

    override suspend fun save(runId: String, cursor: BookingCursor, processed: Long) = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement(
            """
            INSERT INTO backfill_runs (run_id, cursor_at, cursor_id, processed) VALUES (?, ?, ?, ?)
            ON CONFLICT (run_id) DO UPDATE SET cursor_at = EXCLUDED.cursor_at, cursor_id = EXCLUDED.cursor_id, processed = EXCLUDED.processed, updated_at = now()
            """.trimIndent(),
        ).use { st ->
            st.setString(1, runId)
            st.setObject(2, cursor.createdAt.atOffset(ZoneOffset.UTC))
            st.setObject(3, cursor.id.value.toJavaUuid())
            st.setLong(4, processed)
            st.executeUpdate()
        }
        Unit
    }

    override suspend fun complete(runId: String, at: Instant) = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("UPDATE backfill_runs SET completed_at = ?, updated_at = now() WHERE run_id = ?").use { st ->
            st.setObject(1, at.atOffset(ZoneOffset.UTC))
            st.setString(2, runId)
            st.executeUpdate()
        }
        Unit
    }
}
