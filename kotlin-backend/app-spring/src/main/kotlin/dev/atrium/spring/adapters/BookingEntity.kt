package dev.atrium.spring.adapters

import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.PaymentId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import dev.atrium.infrastructure.postgres.code
import org.springframework.data.annotation.Id
import org.springframework.data.annotation.Version
import org.springframework.data.jdbc.repository.query.Query
import org.springframework.data.relational.core.mapping.Table
import org.springframework.data.repository.CrudRepository
import java.time.Instant
import java.util.UUID
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

/** Persistence-модель Spring Data JDBC: плоская, без value classes; домен — отдельный Booking. */
@Table("bookings")
data class BookingEntity(
    @Id val id: UUID,
    val roomId: UUID,
    val memberId: UUID,
    val slot: TimeSlot,
    val status: String,
    val expiresAt: Instant?,
    val paymentId: String?,
    val cancelReason: String?,
    val cancelledAt: Instant?,
    @Version val version: Long,
    val createdAt: Instant,
)

interface BookingEntityRepository : CrudRepository<BookingEntity, UUID> {
    @Query("SELECT * FROM bookings WHERE status = 'PENDING' AND expires_at < :now ORDER BY expires_at LIMIT :limit")
    fun findPendingExpiredBefore(now: Instant, limit: Int): List<BookingEntity>
}

fun BookingEntity.toDomain(): Booking = Booking(
    id = BookingId(id.toKotlinUuid()),
    roomId = RoomId(roomId.toKotlinUuid()),
    memberId = MemberId(memberId.toKotlinUuid()),
    slot = slot,
    status = when (status) {
        "PENDING" -> BookingStatus.Pending(requireNotNull(expiresAt))
        "CONFIRMED" -> BookingStatus.Confirmed(PaymentId(requireNotNull(paymentId)))
        "CANCELLED" -> BookingStatus.Cancelled(requireNotNull(cancelReason), requireNotNull(cancelledAt))
        "EXPIRED" -> BookingStatus.Expired
        "NO_SHOW" -> BookingStatus.NoShow
        else -> error("Unknown booking status: $status")
    },
    createdAt = createdAt,
    version = version,
)

fun Booking.toEntity(): BookingEntity = BookingEntity(
    id = id.value.toJavaUuid(),
    roomId = roomId.value.toJavaUuid(),
    memberId = memberId.value.toJavaUuid(),
    slot = slot,
    status = status.code(),
    expiresAt = (status as? BookingStatus.Pending)?.expiresAt,
    paymentId = (status as? BookingStatus.Confirmed)?.paymentId?.value,
    cancelReason = (status as? BookingStatus.Cancelled)?.reason,
    cancelledAt = (status as? BookingStatus.Cancelled)?.at,
    version = version,
    createdAt = createdAt,
)
