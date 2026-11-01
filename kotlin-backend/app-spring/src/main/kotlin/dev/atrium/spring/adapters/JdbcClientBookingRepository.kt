package dev.atrium.spring.adapters

import dev.atrium.application.ports.BookingCursor
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import dev.atrium.infrastructure.postgres.toBooking
import org.springframework.jdbc.core.simple.JdbcClient
import java.time.ZoneOffset
import kotlin.uuid.toJavaUuid

/**
 * Чтение броней через JdbcClient — для не-suspend кода app-spring (Kafka-listener, @Scheduled),
 * где транзакция управляется @Transactional и потоком. Use case-ы используют JdbcBookingRepository.
 */
class JdbcClientBookingRepository(private val jdbc: JdbcClient) {

    fun find(id: BookingId): Booking? =
        jdbc.sql("$SELECT WHERE id = :id")
            .param("id", id.value.toJavaUuid())
            .query { rs, _ -> rs.toBooking() }
            .optional()
            .orElse(null)

    fun findByMember(memberId: MemberId, cursor: BookingCursor?, limit: Int): List<Booking> {
        val spec = if (cursor == null) {
            jdbc.sql("$SELECT WHERE member_id = :member ORDER BY created_at DESC, id DESC LIMIT :limit")
        } else {
            jdbc.sql("$SELECT WHERE member_id = :member AND (created_at, id) < (:createdAt, :cursorId) ORDER BY created_at DESC, id DESC LIMIT :limit")
                .param("createdAt", cursor.createdAt.atOffset(ZoneOffset.UTC))
                .param("cursorId", cursor.id.value.toJavaUuid())
        }
        return spec.param("member", memberId.value.toJavaUuid()).param("limit", limit).query { rs, _ -> rs.toBooking() }.list()
    }

    private companion object {
        const val SELECT = """
            SELECT id, room_id, member_id, lower(slot) AS slot_start, upper(slot) AS slot_end, status,
                   expires_at, payment_id, cancel_reason, cancelled_at, version, created_at
            FROM bookings
        """
    }
}
