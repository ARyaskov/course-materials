package dev.atrium.infrastructure.exposed

import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.OptimisticLockException
import dev.atrium.application.ports.SlotConflictException
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.PaymentId
import dev.atrium.domain.RoomId
import dev.atrium.infrastructure.postgres.code
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.jetbrains.exposed.v1.core.Op
import org.jetbrains.exposed.v1.core.ResultRow
import org.jetbrains.exposed.v1.core.SortOrder
import org.jetbrains.exposed.v1.core.and
import org.jetbrains.exposed.v1.core.eq
import org.jetbrains.exposed.v1.core.greater
import org.jetbrains.exposed.v1.core.inList
import org.jetbrains.exposed.v1.core.less
import org.jetbrains.exposed.v1.core.or
import org.jetbrains.exposed.v1.exceptions.ExposedSQLException
import org.jetbrains.exposed.v1.jdbc.Database
import org.jetbrains.exposed.v1.jdbc.insert
import org.jetbrains.exposed.v1.jdbc.selectAll
import org.jetbrains.exposed.v1.jdbc.transactions.transaction
import org.jetbrains.exposed.v1.jdbc.update
import java.time.Instant
import java.time.ZoneOffset
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

/**
 * Альтернатива JdbcBookingRepository на Exposed 1.0 SQL DSL. Собственная модель транзакций Exposed —
 * в приложении используется либо этот комплект целиком (с ExposedTransactionRunner), либо JDBC-комплект.
 */
class ExposedBookingRepository(private val db: Database, private val dbDispatcher: CoroutineDispatcher) : BookingRepository {

    override suspend fun find(id: BookingId): Booking? = withContext(dbDispatcher) {
        transaction(db) { Bookings.selectAll().where { Bookings.id eq id.value.toJavaUuid() }.singleOrNull()?.toBooking() }
    }

    override suspend fun save(booking: Booking): Booking = withContext(dbDispatcher) {
        transaction(db) {
            val uuid = booking.id.value.toJavaUuid()
            val exists = Bookings.selectAll().where { Bookings.id eq uuid }.count() > 0
            if (!exists) {
                try {
                    Bookings.insert {
                        it[id] = uuid
                        it[roomId] = booking.roomId.value.toJavaUuid()
                        it[memberId] = booking.memberId.value.toJavaUuid()
                        it[slot] = booking.slot
                        it[status] = booking.status.code()
                        it[expiresAt] = (booking.status as? BookingStatus.Pending)?.expiresAt?.atOffset(ZoneOffset.UTC)
                        it[paymentId] = (booking.status as? BookingStatus.Confirmed)?.paymentId?.value
                        it[cancelReason] = (booking.status as? BookingStatus.Cancelled)?.reason
                        it[cancelledAt] = (booking.status as? BookingStatus.Cancelled)?.at?.atOffset(ZoneOffset.UTC)
                        it[version] = 1
                        it[createdAt] = booking.createdAt.atOffset(ZoneOffset.UTC)
                    }
                } catch (e: ExposedSQLException) {
                    if (e.sqlState == "23P01") throw SlotConflictException(booking.roomId, booking.slot, e) else throw e
                }
                booking.copy(version = 1)
            } else {
                val updated = Bookings.update({ (Bookings.id eq uuid) and (Bookings.version eq booking.version) }) {
                    it[status] = booking.status.code()
                    it[expiresAt] = (booking.status as? BookingStatus.Pending)?.expiresAt?.atOffset(ZoneOffset.UTC)
                    it[paymentId] = (booking.status as? BookingStatus.Confirmed)?.paymentId?.value
                    it[cancelReason] = (booking.status as? BookingStatus.Cancelled)?.reason
                    it[cancelledAt] = (booking.status as? BookingStatus.Cancelled)?.at?.atOffset(ZoneOffset.UTC)
                    it[version] = booking.version + 1
                }
                if (updated == 0) throw OptimisticLockException(booking.id)
                booking.copy(version = booking.version + 1)
            }
        }
    }

    override suspend fun findActiveByRoom(roomId: RoomId, from: Instant, to: Instant): List<Booking> = withContext(dbDispatcher) {
        transaction(db) {
            Bookings.selectAll()
                .where { (Bookings.roomId eq roomId.value.toJavaUuid()) and (Bookings.status inList ACTIVE) and (Bookings.slot overlaps dev.atrium.domain.TimeSlot(from, to)) }
                .orderBy(Bookings.createdAt)
                .map { it.toBooking() }
        }
    }

    override suspend fun findActiveByRooms(roomIds: Collection<RoomId>, from: Instant, to: Instant): Map<RoomId, List<Booking>> = withContext(dbDispatcher) {
        transaction(db) {
            Bookings.selectAll()
                .where { (Bookings.roomId inList roomIds.map { it.value.toJavaUuid() }) and (Bookings.status inList ACTIVE) and (Bookings.slot overlaps dev.atrium.domain.TimeSlot(from, to)) }
                .map { it.toBooking() }
                .groupBy { it.roomId }
        }
    }

    override suspend fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking> = withContext(dbDispatcher) {
        transaction(db) {
            Bookings.selectAll()
                .where {
                    var condition: Op<Boolean> = Bookings.memberId eq memberId.value.toJavaUuid()
                    if (cursor != null) {
                        val at = cursor.createdAt.atOffset(ZoneOffset.UTC)
                        condition = condition and ((Bookings.createdAt less at) or ((Bookings.createdAt eq at) and (Bookings.id less cursor.id.value.toJavaUuid())))
                    }
                    condition
                }
                .orderBy(Bookings.createdAt to SortOrder.DESC, Bookings.id to SortOrder.DESC)
                .limit(limit)
                .map { it.toBooking() }
        }
    }

    override suspend fun findPendingExpiredBefore(now: Instant, limit: Int): List<Booking> = withContext(dbDispatcher) {
        transaction(db) {
            Bookings.selectAll()
                .where { (Bookings.status eq "PENDING") and (Bookings.expiresAt less now.atOffset(ZoneOffset.UTC)) }
                .orderBy(Bookings.expiresAt)
                .limit(limit)
                .forUpdate() // SKIP LOCKED — через exec("…") при необходимости; см. урок 9.4
                .map { it.toBooking() }
        }
    }

    override fun streamCreatedBetween(from: Instant, to: Instant, batchSize: Int, after: BookingCursor?): Flow<Booking> = flow {
        var cursor: BookingCursor? = after
        while (true) {
            val batch = withContext(dbDispatcher) {
                transaction(db) {
                    Bookings.selectAll()
                        .where {
                            var condition: Op<Boolean> = (Bookings.createdAt greater from.atOffset(ZoneOffset.UTC)) and (Bookings.createdAt less to.atOffset(ZoneOffset.UTC))
                            cursor?.let { c ->
                                val at = c.createdAt.atOffset(ZoneOffset.UTC)
                                condition = condition and ((Bookings.createdAt greater at) or ((Bookings.createdAt eq at) and (Bookings.id greater c.id.value.toJavaUuid())))
                            }
                            condition
                        }
                        .orderBy(Bookings.createdAt to SortOrder.ASC, Bookings.id to SortOrder.ASC)
                        .limit(batchSize)
                        .map { it.toBooking() }
                }
            }
            if (batch.isEmpty()) break
            batch.forEach { emit(it) }
            cursor = BookingCursor(batch.last().createdAt, batch.last().id)
        }
    }

    private fun ResultRow.toBooking(): Booking = Booking(
        id = BookingId(this[Bookings.id].toKotlinUuid()),
        roomId = RoomId(this[Bookings.roomId].toKotlinUuid()),
        memberId = MemberId(this[Bookings.memberId].toKotlinUuid()),
        slot = this[Bookings.slot],
        status = when (val code = this[Bookings.status]) {
            "PENDING" -> BookingStatus.Pending(requireNotNull(this[Bookings.expiresAt]) { "expires_at is null for PENDING" }.toInstant())
            "CONFIRMED" -> BookingStatus.Confirmed(PaymentId(requireNotNull(this[Bookings.paymentId]) { "payment_id is null for CONFIRMED" }))
            "CANCELLED" -> BookingStatus.Cancelled(requireNotNull(this[Bookings.cancelReason]), requireNotNull(this[Bookings.cancelledAt]).toInstant())
            "EXPIRED" -> BookingStatus.Expired
            "NO_SHOW" -> BookingStatus.NoShow
            else -> error("Unknown booking status: $code")
        },
        createdAt = this[Bookings.createdAt].toInstant(),
        version = this[Bookings.version],
    )

    private companion object {
        val ACTIVE = listOf("PENDING", "CONFIRMED")
    }
}
