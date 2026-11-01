package dev.atrium.ktor.api

import dev.atrium.domain.Booking
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.Room
import dev.atrium.infrastructure.postgres.code
import kotlinx.serialization.Serializable

@Serializable
data class CreateBookingRequest(
    val roomId: String,
    val startsAt: String,
    val durationMinutes: Int = 60,
    val comment: String? = null,
)

@Serializable
data class BookingResponse(
    val id: String,
    val roomId: String,
    val memberId: String,
    val startsAt: String,
    val endsAt: String,
    val status: String,
    val expiresAt: String? = null,
    val paymentId: String? = null,
    val createdAt: String,
)

@Serializable
data class RoomResponse(
    val id: String,
    val locationId: String,
    val name: String,
    val capacity: Int,
    val pricePerHour: String,
    val amenities: List<String>,
)

fun Booking.toResponse(): BookingResponse = BookingResponse(
    id = id.value.toString(),
    roomId = roomId.value.toString(),
    memberId = memberId.value.toString(),
    startsAt = slot.start.toString(),
    endsAt = slot.end.toString(),
    status = status.code(),
    expiresAt = (status as? BookingStatus.Pending)?.expiresAt?.toString(),
    paymentId = (status as? BookingStatus.Confirmed)?.paymentId?.value,
    createdAt = createdAt.toString(),
)

fun Room.toResponse(): RoomResponse = RoomResponse(
    id = id.value.toString(),
    locationId = locationId.value.toString(),
    name = name,
    capacity = capacity,
    pricePerHour = pricePerHour.toString(),
    amenities = amenities.sorted(),
)

@Serializable
data class CancelBookingRequest(val reason: String)

@Serializable
data class PageResponse<T>(val items: List<T>, val nextCursor: String? = null)

fun CreateBookingRequest.toCommand(memberId: dev.atrium.domain.MemberId): dev.atrium.application.CreateBookingCommand =
    dev.atrium.application.CreateBookingCommand(
        roomId = requireNotNull(dev.atrium.domain.RoomId.parse(roomId)) { "roomId validated before mapping" },
        memberId = memberId,
        slot = dev.atrium.domain.TimeSlot.of(java.time.Instant.parse(startsAt), java.time.Duration.ofMinutes(durationMinutes.toLong())),
        comment = comment,
    )
