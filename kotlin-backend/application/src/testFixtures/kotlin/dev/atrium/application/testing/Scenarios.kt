package dev.atrium.application.testing

import dev.atrium.application.ports.BookingRepository
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.Room
import dev.atrium.domain.aBooking
import dev.atrium.domain.aConfirmedBooking
import java.time.Duration
import java.time.Instant
import kotlin.uuid.Uuid

data class MemberWithBookings(val memberId: MemberId, val room: Room, val pending: Booking, val confirmed: Booking, val cancelled: Booking)

/** Участник с бронями во всех активных и неактивных статусах — для тестов списков, фильтров и переходов. */
suspend fun BookingRepository.seedMemberWithBookings(room: Room, now: Instant): MemberWithBookings {
    val member = MemberId(Uuid.random())
    val pending = save(aBooking { roomId = room.id; memberId = member; slot(now + Duration.ofHours(1)) })
    val confirmed = save(aConfirmedBooking { roomId = room.id; memberId = member; slot(now + Duration.ofHours(3)); createdAt = now - Duration.ofHours(1) })
    val cancelled = save(aBooking { roomId = room.id; memberId = member; slot(now + Duration.ofHours(5)); status = BookingStatus.Cancelled("user", now); createdAt = now - Duration.ofHours(2) })
    return MemberWithBookings(member, room, pending, confirmed, cancelled)
}
