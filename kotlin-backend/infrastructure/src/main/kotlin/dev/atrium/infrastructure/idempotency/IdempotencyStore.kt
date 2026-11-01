package dev.atrium.infrastructure.idempotency

import dev.atrium.application.ports.IdempotencyOutcome
import dev.atrium.application.ports.IdempotencyStore
import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import dev.atrium.infrastructure.postgres.withConnection
import kotlinx.coroutines.CoroutineDispatcher
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

class JdbcIdempotencyStore(
    private val dataSource: DataSource,
    private val dbDispatcher: CoroutineDispatcher,
    private val ttl: Duration = Duration.ofHours(24),
    private val staleAfter: Duration = Duration.ofSeconds(30),
) : IdempotencyStore {

    /** Атомарная попытка занять ключ: INSERT … ON CONFLICT DO NOTHING; при конфликте — читаем состояние. */
    override suspend fun begin(memberId: MemberId, key: String, requestHash: String): IdempotencyOutcome = dataSource.withConnection(dbDispatcher) { connection ->
        val inserted = connection.prepareStatement(
            "INSERT INTO idempotency_keys (member_id, key, request_hash, expires_at) VALUES (?, ?, ?, now() + ?::interval) ON CONFLICT DO NOTHING",
        ).use { st ->
            st.setObject(1, memberId.value.toJavaUuid())
            st.setString(2, key)
            st.setString(3, requestHash)
            st.setString(4, "${ttl.toHours()} hours")
            st.executeUpdate()
        }
        if (inserted == 1) return@withConnection IdempotencyOutcome.Acquired

        connection.prepareStatement("SELECT request_hash, booking_id, response_status, completed_at, locked_at FROM idempotency_keys WHERE member_id = ? AND key = ?").use { st ->
            st.setObject(1, memberId.value.toJavaUuid())
            st.setString(2, key)
            st.executeQuery().use { rs ->
                rs.next()
                val bookingId = rs.getObject("booking_id", UUID::class.java)
                when {
                    rs.getString("request_hash") != requestHash -> IdempotencyOutcome.Mismatch
                    rs.getObject("completed_at") != null && bookingId != null -> IdempotencyOutcome.Replay(BookingId(bookingId.toKotlinUuid()), rs.getInt("response_status"))
                    rs.getObject("locked_at", OffsetDateTime::class.java).toInstant() < Instant.now().minus(staleAfter) -> IdempotencyOutcome.Acquired // зависшая — перезанять
                    else -> IdempotencyOutcome.InProgress
                }
            }
        }
    }

    override suspend fun complete(memberId: MemberId, key: String, bookingId: BookingId, status: Int) = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("UPDATE idempotency_keys SET booking_id = ?, response_status = ?, completed_at = now() WHERE member_id = ? AND key = ?").use { st ->
            st.setObject(1, bookingId.value.toJavaUuid())
            st.setInt(2, status)
            st.setObject(3, memberId.value.toJavaUuid())
            st.setString(4, key)
            st.executeUpdate()
        }
        Unit
    }
}
