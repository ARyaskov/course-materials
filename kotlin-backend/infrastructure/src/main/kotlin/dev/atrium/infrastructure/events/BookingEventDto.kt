package dev.atrium.infrastructure.events

import com.fasterxml.jackson.annotation.JsonSubTypes
import com.fasterxml.jackson.annotation.JsonTypeInfo
import dev.atrium.application.ports.BookingEvent
import java.time.Instant

/** Контракт топика atrium.bookings — публичный, как HTTP API; отдельный от доменного BookingEvent. */
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes(
    JsonSubTypes.Type(BookingEventDto.Created::class, name = "booking.created"),
    JsonSubTypes.Type(BookingEventDto.Confirmed::class, name = "booking.confirmed"),
    JsonSubTypes.Type(BookingEventDto.Cancelled::class, name = "booking.cancelled"),
    JsonSubTypes.Type(BookingEventDto.Expired::class, name = "booking.expired"),
)
sealed interface BookingEventDto {
    val eventId: String
    val bookingId: String
    val occurredAt: Instant
    val schemaVersion: Int

    fun type(): String = when (this) {
        is Created -> "booking.created"
        is Confirmed -> "booking.confirmed"
        is Cancelled -> "booking.cancelled"
        is Expired -> "booking.expired"
    }

    data class Created(
        override val eventId: String,
        override val bookingId: String,
        val roomId: String,
        val memberId: String,
        val startsAt: Instant,
        val endsAt: Instant,
        override val occurredAt: Instant,
        override val schemaVersion: Int = 1,
    ) : BookingEventDto

    data class Confirmed(override val eventId: String, override val bookingId: String, override val occurredAt: Instant, override val schemaVersion: Int = 1) : BookingEventDto
    data class Cancelled(override val eventId: String, override val bookingId: String, val reason: String, override val occurredAt: Instant, override val schemaVersion: Int = 1) : BookingEventDto
    data class Expired(override val eventId: String, override val bookingId: String, override val occurredAt: Instant, override val schemaVersion: Int = 1) : BookingEventDto
}

fun BookingEvent.toDto(): BookingEventDto = when (this) {
    is BookingEvent.Created -> BookingEventDto.Created(eventId.toString(), bookingId.value.toString(), roomId.value.toString(), memberId.value.toString(), slot.start, slot.end, occurredAt)
    is BookingEvent.Confirmed -> BookingEventDto.Confirmed(eventId.toString(), bookingId.value.toString(), occurredAt)
    is BookingEvent.Cancelled -> BookingEventDto.Cancelled(eventId.toString(), bookingId.value.toString(), reason, occurredAt)
    is BookingEvent.Expired -> BookingEventDto.Expired(eventId.toString(), bookingId.value.toString(), occurredAt)
}

/** Отправка в брокер — реализации: Spring KafkaTemplate или KafkaProducer напрямую. */
interface BookingEventSender {
    suspend fun send(event: BookingEventDto)
}
