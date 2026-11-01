package dev.atrium.infrastructure.jooq

import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.OptimisticLockException
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.PaymentId
import dev.atrium.domain.RoomId
import dev.atrium.infrastructure.jooq.generated.tables.records.BookingsRecord
import dev.atrium.infrastructure.jooq.generated.tables.references.BOOKINGS
import dev.atrium.infrastructure.postgres.code
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import org.jooq.DSLContext
import org.jooq.impl.DSL.condition
import org.jooq.impl.DSL.noCondition
import org.jooq.impl.DSL.row
import org.jooq.impl.DSL.`val`
import java.time.Instant
import java.time.ZoneOffset.UTC
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

/**
 * Репозиторий на jOOQ: типы и nullability — из классов, сгенерированных scripts/jooq-codegen.sh.
 * DSLContext создаётся на соединении текущей транзакции (JdbcTransaction) — jOOQ не навязывает свою модель транзакций.
 */
class JooqBookingRepository(private val dsl: DSLContext, private val dbDispatcher: CoroutineDispatcher) : BookingRepository {

    override suspend fun find(id: BookingId): Booking? = withContext(dbDispatcher) {
        dsl.selectFrom(BOOKINGS).where(BOOKINGS.ID.eq(id.value.toJavaUuid())).fetchOne()?.toBooking()
    }

    override suspend fun save(booking: Booking): Booking = withContext(dbDispatcher) {
        val uuid = booking.id.value.toJavaUuid()
        if (booking.version == 0L && dsl.fetchCount(BOOKINGS, BOOKINGS.ID.eq(uuid)) == 0) {
            dsl.insertInto(BOOKINGS)
                .set(BOOKINGS.ID, uuid)
                .set(BOOKINGS.ROOM_ID, booking.roomId.value.toJavaUuid())
                .set(BOOKINGS.MEMBER_ID, booking.memberId.value.toJavaUuid())
                .set(BOOKINGS.SLOT, booking.slot)
                .set(BOOKINGS.STATUS, booking.status.code())
                .set(BOOKINGS.EXPIRES_AT, (booking.status as? BookingStatus.Pending)?.expiresAt?.atOffset(UTC))
                .set(BOOKINGS.PAYMENT_ID, (booking.status as? BookingStatus.Confirmed)?.paymentId?.value)
                .set(BOOKINGS.VERSION, 1L)
                .set(BOOKINGS.CREATED_AT, booking.createdAt.atOffset(UTC))
                .execute()
            booking.copy(version = 1)
        } else {
            val updated = dsl.update(BOOKINGS)
                .set(BOOKINGS.STATUS, booking.status.code())
                .set(BOOKINGS.EXPIRES_AT, (booking.status as? BookingStatus.Pending)?.expiresAt?.atOffset(UTC))
                .set(BOOKINGS.PAYMENT_ID, (booking.status as? BookingStatus.Confirmed)?.paymentId?.value)
                .set(BOOKINGS.CANCEL_REASON, (booking.status as? BookingStatus.Cancelled)?.reason)
                .set(BOOKINGS.CANCELLED_AT, (booking.status as? BookingStatus.Cancelled)?.at?.atOffset(UTC))
                .set(BOOKINGS.VERSION, booking.version + 1)
                .where(BOOKINGS.ID.eq(uuid)).and(BOOKINGS.VERSION.eq(booking.version))
                .execute()
            if (updated == 0) throw OptimisticLockException(booking.id)
            booking.copy(version = booking.version + 1)
        }
    }

    override suspend fun findActiveByRoom(roomId: RoomId, from: Instant, to: Instant): List<Booking> = withContext(dbDispatcher) {
        dsl.selectFrom(BOOKINGS)
            .where(BOOKINGS.ROOM_ID.eq(roomId.value.toJavaUuid()))
            .and(BOOKINGS.STATUS.`in`("PENDING", "CONFIRMED"))
            .and(condition("{0} && tstzrange({1}, {2}, '[)')", BOOKINGS.SLOT, `val`(from.atOffset(UTC)), `val`(to.atOffset(UTC))))
            .orderBy(BOOKINGS.CREATED_AT)
            .fetch { it.toBooking() }
    }

    override suspend fun findActiveByRooms(roomIds: Collection<RoomId>, from: Instant, to: Instant): Map<RoomId, List<Booking>> = withContext(dbDispatcher) {
        dsl.selectFrom(BOOKINGS)
            .where(BOOKINGS.ROOM_ID.`in`(roomIds.map { it.value.toJavaUuid() }))
            .and(BOOKINGS.STATUS.`in`("PENDING", "CONFIRMED"))
            .and(condition("{0} && tstzrange({1}, {2}, '[)')", BOOKINGS.SLOT, `val`(from.atOffset(UTC)), `val`(to.atOffset(UTC))))
            .fetch { it.toBooking() }
            .groupBy { it.roomId }
    }

    override suspend fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking> = withContext(dbDispatcher) {
        dsl.selectFrom(BOOKINGS)
            .where(BOOKINGS.MEMBER_ID.eq(memberId.value.toJavaUuid()))
            .and(cursor?.let { row(BOOKINGS.CREATED_AT, BOOKINGS.ID).lt(it.createdAt.atOffset(UTC), it.id.value.toJavaUuid()) } ?: noCondition())
            .orderBy(BOOKINGS.CREATED_AT.desc(), BOOKINGS.ID.desc())
            .limit(limit)
            .fetch { it.toBooking() }
    }

    override suspend fun findPendingExpiredBefore(now: Instant, limit: Int): List<Booking> = withContext(dbDispatcher) {
        dsl.selectFrom(BOOKINGS)
            .where(BOOKINGS.STATUS.eq("PENDING")).and(BOOKINGS.EXPIRES_AT.lt(now.atOffset(UTC)))
            .orderBy(BOOKINGS.EXPIRES_AT)
            .limit(limit)
            .forUpdate().skipLocked()
            .fetch { it.toBooking() }
    }

    override fun streamCreatedBetween(from: Instant, to: Instant, batchSize: Int, after: BookingCursor?): Flow<Booking> = flow {
        var cursor: BookingCursor? = after
        while (true) {
            val batch = withContext(dbDispatcher) {
                dsl.selectFrom(BOOKINGS)
                    .where(BOOKINGS.CREATED_AT.ge(from.atOffset(UTC))).and(BOOKINGS.CREATED_AT.lt(to.atOffset(UTC)))
                    .and(cursor?.let { row(BOOKINGS.CREATED_AT, BOOKINGS.ID).gt(it.createdAt.atOffset(UTC), it.id.value.toJavaUuid()) } ?: noCondition())
                    .orderBy(BOOKINGS.CREATED_AT, BOOKINGS.ID)
                    .limit(batchSize)
                    .fetch { it.toBooking() }
            }
            if (batch.isEmpty()) break
            batch.forEach { emit(it) }
            cursor = BookingCursor(batch.last().createdAt, batch.last().id)
        }
    }

    private fun BookingsRecord.toBooking(): Booking = Booking(
        id = BookingId(id.toKotlinUuid()),
        roomId = RoomId(roomId.toKotlinUuid()),
        memberId = MemberId(memberId.toKotlinUuid()),
        slot = slot,
        status = when (status) {
            "PENDING" -> BookingStatus.Pending(requireNotNull(expiresAt) { "expires_at is null for PENDING" }.toInstant())
            "CONFIRMED" -> BookingStatus.Confirmed(PaymentId(requireNotNull(paymentId) { "payment_id is null for CONFIRMED" }))
            "CANCELLED" -> BookingStatus.Cancelled(requireNotNull(cancelReason), requireNotNull(cancelledAt).toInstant())
            "EXPIRED" -> BookingStatus.Expired
            "NO_SHOW" -> BookingStatus.NoShow
            else -> error("Unknown booking status: $status")
        },
        createdAt = createdAt.toInstant(),
        version = requireNotNull(version) { "version is null for persisted booking" },
    )
}
