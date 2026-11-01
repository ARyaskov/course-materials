package dev.atrium.ktor.api

import dev.atrium.domain.RoomId
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.format.DateTimeParseException

@Serializable
data class FieldError(val field: String, val code: String, val message: String)

private fun parseInstantOrNull(raw: String): Instant? =
    try { Instant.parse(raw) } catch (_: DateTimeParseException) { null }

/** Все нарушения формы собираются в один список — клиент исправляет запрос за один раз. */
fun CreateBookingRequest.validate(): List<FieldError> = buildList {
    if (roomId.isBlank()) add(FieldError("roomId", "required", "roomId must not be blank"))
    else if (RoomId.parse(roomId) == null) add(FieldError("roomId", "format", "roomId must be a UUID"))
    if (parseInstantOrNull(startsAt) == null) add(FieldError("startsAt", "format", "startsAt must be ISO-8601"))
    if (durationMinutes !in 15..480) add(FieldError("durationMinutes", "range", "durationMinutes must be in 15..480"))
    if ((comment?.length ?: 0) > 500) add(FieldError("comment", "size", "comment must be at most 500 chars"))
}
