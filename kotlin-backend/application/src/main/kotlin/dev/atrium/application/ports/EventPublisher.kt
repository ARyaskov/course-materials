package dev.atrium.application.ports

import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import java.time.Instant
import kotlin.uuid.Uuid

sealed interface BookingEvent {
    /** Уникальный идентификатор события — ключ дедупликации на стороне consumer-ов. */
    val eventId: Uuid
    val bookingId: BookingId
    val occurredAt: Instant

    data class Created(
        override val bookingId: BookingId,
        val roomId: RoomId,
        val memberId: MemberId,
        val slot: TimeSlot,
        override val occurredAt: Instant,
        override val eventId: Uuid = Uuid.random(),
    ) : BookingEvent

    data class Confirmed(
        override val bookingId: BookingId,
        override val occurredAt: Instant,
        override val eventId: Uuid = Uuid.random(),
    ) : BookingEvent

    data class Cancelled(
        override val bookingId: BookingId,
        val reason: String,
        override val occurredAt: Instant,
        override val eventId: Uuid = Uuid.random(),
    ) : BookingEvent

    data class Expired(
        override val bookingId: BookingId,
        override val occurredAt: Instant,
        override val eventId: Uuid = Uuid.random(),
    ) : BookingEvent
}

/** Публикация доменных событий. Реализация в infrastructure пишет в outbox в текущей транзакции. */
interface EventPublisher {
    suspend fun publish(event: BookingEvent)
}
