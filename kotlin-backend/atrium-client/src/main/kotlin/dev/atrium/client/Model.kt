package dev.atrium.client

import java.time.Instant
import kotlin.uuid.Uuid

/** Ссылка на бронь для Java: обычный класс вместо value class BookingId (урок 16.5). */
public class BookingRef(public val id: Uuid, public val roomId: Uuid, public val startsAt: Instant, public val endsAt: Instant, public val status: String) {
    override fun toString(): String = "BookingRef($id, $status)"
}

/** Problem Details RFC 9457 в ответе 4xx. */
public class Problem(public val type: String, public val title: String, public val status: Int, public val detail: String?) {
    override fun toString(): String = "Problem($type, $status)"
}

/** Закрытое по бизнес-смыслу множество: Java 21+ switch исчерпывающий (Kotlin 2.4 пишет PermittedSubclasses). */
public sealed class BookingResult {
    public class Created(public val booking: BookingRef) : BookingResult()
    public class Rejected(public val problem: Problem) : BookingResult()
}

/** Запрос — builder для Java, именованные аргументы для Kotlin; не data class ради бинарной совместимости. */
public class CreateBookingRequest private constructor(public val roomId: Uuid, public val startsAt: Instant, public val durationMinutes: Int) {
    public class Builder {
        private var roomId: Uuid? = null
        private var startsAt: Instant? = null
        private var durationMinutes: Int = 60
        public fun roomId(value: Uuid): Builder = apply { roomId = value }
        public fun startsAt(value: Instant): Builder = apply { startsAt = value }
        public fun durationMinutes(value: Int): Builder = apply { durationMinutes = value }
        public fun build(): CreateBookingRequest = CreateBookingRequest(requireNotNull(roomId) { "roomId" }, requireNotNull(startsAt) { "startsAt" }, durationMinutes)
    }

    public companion object {
        @JvmStatic public fun builder(): Builder = Builder()

        /** Для Kotlin — именованные аргументы без builder-а. */
        public fun of(roomId: Uuid, startsAt: Instant, durationMinutes: Int = 60): CreateBookingRequest = CreateBookingRequest(roomId, startsAt, durationMinutes)
    }
}

public class OccupancyEvent(public val roomId: Uuid, public val occupied: Boolean, public val at: Instant)
