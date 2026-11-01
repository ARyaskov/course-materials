package dev.atrium.infrastructure.postgres

import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.OptimisticLockException
import dev.atrium.application.ports.SlotConflictException
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.RoomId
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.sql.Connection
import java.sql.PreparedStatement
import java.sql.ResultSet
import java.sql.SQLException
import java.time.Instant
import java.time.ZoneOffset
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid

/**
 * Эталонный репозиторий на чистом JDBC. Соединение — из текущей транзакции (JdbcTransaction в контексте)
 * или из пула; блокирующие вызовы — на dbDispatcher (virtual threads, лимит = размер пула).
 */
class JdbcBookingRepository(
    private val dataSource: DataSource,
    private val dbDispatcher: CoroutineDispatcher,
) : BookingRepository {

    override suspend fun find(id: BookingId): Booking? = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("$SELECT WHERE id = ?").use { statement ->
            statement.setObject(1, id.value.toJavaUuid())
            statement.executeQuery().use { rs -> if (rs.next()) rs.toBooking() else null }
        }
    }

    override suspend fun save(booking: Booking): Booking = dataSource.withConnection(dbDispatcher) { connection ->
        if (booking.version == 0L && !exists(connection, booking.id)) insert(connection, booking) else update(connection, booking)
    }

    override suspend fun findActiveByRoom(roomId: RoomId, from: Instant, to: Instant): List<Booking> =
        dataSource.withConnection(dbDispatcher) { connection ->
            connection.prepareStatement(
                "$SELECT WHERE room_id = ? AND status IN ('PENDING','CONFIRMED') AND slot && tstzrange(?, ?, '[)') ORDER BY lower(slot)",
            ).use { statement ->
                statement.setObject(1, roomId.value.toJavaUuid())
                statement.setObject(2, from.atOffset(ZoneOffset.UTC))
                statement.setObject(3, to.atOffset(ZoneOffset.UTC))
                statement.executeQuery().use { it.toBookings() }
            }
        }

    override suspend fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking> =
        dataSource.withConnection(dbDispatcher) { connection ->
            val sql = buildString {
                append("$SELECT WHERE member_id = ?")
                if (cursor != null) append(" AND (created_at, id) < (?, ?)")
                append(" ORDER BY created_at DESC, id DESC LIMIT ?")
            }
            connection.prepareStatement(sql).use { statement ->
                var i = 1
                statement.setObject(i++, memberId.value.toJavaUuid())
                if (cursor != null) {
                    statement.setObject(i++, cursor.createdAt.atOffset(ZoneOffset.UTC))
                    statement.setObject(i++, cursor.id.value.toJavaUuid())
                }
                statement.setInt(i, limit)
                statement.executeQuery().use { it.toBookings() }
            }
        }

    override suspend fun findActiveByRooms(roomIds: Collection<RoomId>, from: Instant, to: Instant): Map<RoomId, List<Booking>> =
        dataSource.withConnection(dbDispatcher) { connection ->
            connection.prepareStatement(
                "$SELECT WHERE room_id = ANY(?) AND status IN ('PENDING','CONFIRMED') AND slot && tstzrange(?, ?, '[)') ORDER BY room_id, lower(slot)",
            ).use { statement ->
                statement.setArray(1, connection.createArrayOf("uuid", roomIds.map { it.value.toJavaUuid() }.toTypedArray()))
                statement.setObject(2, from.atOffset(ZoneOffset.UTC))
                statement.setObject(3, to.atOffset(ZoneOffset.UTC))
                statement.executeQuery().use { it.toBookings() }.groupBy { it.roomId }
            }
        }

    override suspend fun findPendingExpiredBefore(now: Instant, limit: Int): List<Booking> =
        dataSource.withConnection(dbDispatcher) { connection ->
            connection.prepareStatement("$SELECT WHERE status = 'PENDING' AND expires_at < ? ORDER BY expires_at LIMIT ? FOR UPDATE SKIP LOCKED")
                .use { statement ->
                    statement.setObject(1, now.atOffset(ZoneOffset.UTC))
                    statement.setInt(2, limit)
                    statement.executeQuery().use { it.toBookings() }
                }
        }

    override fun streamCreatedBetween(from: Instant, to: Instant, batchSize: Int, after: BookingCursor?): Flow<Booking> = flow {
        var cursor: BookingCursor? = after
        while (true) {
            // Соединение открывается на каждый батч и закрывается между emit
            val batch = dataSource.withConnection(dbDispatcher) { connection -> loadBatch(connection, from, to, cursor, batchSize) }
            if (batch.isEmpty()) break
            batch.forEach { emit(it) }
            cursor = BookingCursor(batch.last().createdAt, batch.last().id)
        }
    }

    private fun loadBatch(connection: Connection, from: Instant, to: Instant, cursor: BookingCursor?, batchSize: Int): List<Booking> {
        val sql = buildString {
            append("$SELECT WHERE created_at >= ? AND created_at < ?")
            if (cursor != null) append(" AND (created_at, id) > (?, ?)")
            append(" ORDER BY created_at, id LIMIT ?")
        }
        return connection.prepareStatement(sql).use { statement ->
            var i = 1
            statement.setObject(i++, from.atOffset(ZoneOffset.UTC))
            statement.setObject(i++, to.atOffset(ZoneOffset.UTC))
            if (cursor != null) {
                statement.setObject(i++, cursor.createdAt.atOffset(ZoneOffset.UTC))
                statement.setObject(i++, cursor.id.value.toJavaUuid())
            }
            statement.setInt(i, batchSize)
            statement.executeQuery().use { it.toBookings() }
        }
    }

    private fun exists(connection: Connection, id: BookingId): Boolean =
        connection.prepareStatement("SELECT 1 FROM bookings WHERE id = ?").use { statement ->
            statement.setObject(1, id.value.toJavaUuid())
            statement.executeQuery().use { it.next() }
        }

    private fun insert(connection: Connection, booking: Booking): Booking = try {
        connection.prepareStatement(
            """
            INSERT INTO bookings (id, room_id, member_id, slot, status, expires_at, payment_id, cancel_reason, cancelled_at, version, created_at)
            VALUES (?, ?, ?, tstzrange(?, ?, '[)'), ?, ?, ?, ?, ?, 1, ?)
            """.trimIndent(),
        ).use { statement ->
            statement.setObject(1, booking.id.value.toJavaUuid())
            statement.setObject(2, booking.roomId.value.toJavaUuid())
            statement.setObject(3, booking.memberId.value.toJavaUuid())
            statement.setObject(4, booking.slot.start.atOffset(ZoneOffset.UTC))
            statement.setObject(5, booking.slot.end.atOffset(ZoneOffset.UTC))
            statement.bindStatus(6, booking.status)
            statement.setObject(11, booking.createdAt.atOffset(ZoneOffset.UTC))
            statement.executeUpdate()
        }
        booking.copy(version = 1)
    } catch (e: SQLException) {
        if (e.sqlState == "23P01") throw SlotConflictException(booking.roomId, booking.slot, e) else throw e
    }

    private fun update(connection: Connection, booking: Booking): Booking {
        val updated = connection.prepareStatement(
            """
            UPDATE bookings SET status = ?, expires_at = ?, payment_id = ?, cancel_reason = ?, cancelled_at = ?,
                                version = version + 1, updated_at = now()
            WHERE id = ? AND version = ?
            """.trimIndent(),
        ).use { statement ->
            statement.bindStatus(1, booking.status)
            statement.setObject(6, booking.id.value.toJavaUuid())
            statement.setLong(7, booking.version)
            statement.executeUpdate()
        }
        if (updated == 0) throw OptimisticLockException(booking.id)
        return booking.copy(version = booking.version + 1)
    }

    /** Разворачивает sealed-статус в пять колонок: status, expires_at, payment_id, cancel_reason, cancelled_at. */
    private fun PreparedStatement.bindStatus(from: Int, status: BookingStatus) {
        setString(from, status.code())
        setObject(from + 1, (status as? BookingStatus.Pending)?.expiresAt?.atOffset(ZoneOffset.UTC))
        setString(from + 2, (status as? BookingStatus.Confirmed)?.paymentId?.value)
        setString(from + 3, (status as? BookingStatus.Cancelled)?.reason)
        setObject(from + 4, (status as? BookingStatus.Cancelled)?.at?.atOffset(ZoneOffset.UTC))
    }

    private fun ResultSet.toBookings(): List<Booking> = buildList { while (next()) add(toBooking()) }

    private companion object {
        const val SELECT = """
            SELECT id, room_id, member_id, lower(slot) AS slot_start, upper(slot) AS slot_end, status,
                   expires_at, payment_id, cancel_reason, cancelled_at, version, created_at
            FROM bookings
        """
    }
}
