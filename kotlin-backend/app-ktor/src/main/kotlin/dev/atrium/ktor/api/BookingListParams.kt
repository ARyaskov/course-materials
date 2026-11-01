package dev.atrium.ktor.api

import dev.atrium.application.BookingFilter
import dev.atrium.application.BookingSort
import dev.atrium.application.BookingStatusCode
import dev.atrium.application.ListQuery
import dev.atrium.application.Outcome
import dev.atrium.application.SortDirection
import io.ktor.http.Parameters
import java.time.Instant
import java.time.format.DateTimeParseException

private fun parseInstant(raw: String): Instant? = try { Instant.parse(raw) } catch (_: DateTimeParseException) { null }

/** Ошибки параметров накапливаются, как в валидации тела: клиент исправляет всё за один раз. */
fun Parameters.toListQuery(): Outcome<ListQuery, List<FieldError>> {
    val errors = mutableListOf<FieldError>()
    val statuses = getAll("status").orEmpty().mapNotNull { raw ->
        BookingStatusCode.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }
            ?: null.also { errors += FieldError("status", "invalid", "unknown status '$raw'") }
    }.toSet()
    val from = this["from"]?.let { parseInstant(it) ?: null.also { errors += FieldError("from", "format", "from must be ISO-8601") } }
    val to = this["to"]?.let { parseInstant(it) ?: null.also { errors += FieldError("to", "format", "to must be ISO-8601") } }
    val (sortField, dir) = (this["sort"] ?: "createdAt:desc").split(':', limit = 2).let { it[0] to (it.getOrNull(1) ?: "desc") }
    val sort = when (sortField) {
        "createdAt" -> BookingSort.CREATED_AT
        "slotStart" -> BookingSort.SLOT_START
        else -> null.also { errors += FieldError("sort", "invalid", "unknown sort field '$sortField'") }
    }
    val limit = this["limit"]?.let { it.toIntOrNull() ?: null.also { errors += FieldError("limit", "format", "limit must be an integer") } } ?: 20
    if (from != null && to != null && from > to) errors += FieldError("from", "range", "from must not be after to")
    if (errors.isNotEmpty() || sort == null) return Outcome.Failure(errors)
    val direction = if (dir.equals("asc", ignoreCase = true)) SortDirection.ASC else SortDirection.DESC
    return Outcome.Success(ListQuery(BookingFilter(statuses, from, to), sort, direction, this["cursor"], limit))
}
