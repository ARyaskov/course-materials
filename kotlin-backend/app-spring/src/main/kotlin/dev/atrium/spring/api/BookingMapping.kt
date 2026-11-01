package dev.atrium.spring.api

import dev.atrium.application.CreateBookingCommand
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import dev.atrium.infrastructure.postgres.code
import java.time.Duration
import kotlin.uuid.Uuid

internal fun Booking.toResponse(): BookingResponse = BookingResponse(
    id = id.value.toString(),
    roomId = roomId.value.toString(),
    memberId = memberId.value.toString(),
    startsAt = slot.start,
    endsAt = slot.end,
    status = status.code(),
    expiresAt = (status as? BookingStatus.Pending)?.expiresAt,
    paymentId = (status as? BookingStatus.Confirmed)?.paymentId?.value,
    createdAt = createdAt,
)

internal fun CreateBookingRequest.toCommand(memberId: MemberId): CreateBookingCommand = CreateBookingCommand(
    roomId = RoomId(Uuid.parse(roomId)),
    memberId = memberId,
    slot = TimeSlot.of(startsAt, Duration.ofMinutes(durationMinutes.toLong())),
    comment = comment,
)
