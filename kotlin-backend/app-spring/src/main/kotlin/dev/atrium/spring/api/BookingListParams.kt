package dev.atrium.spring.api

import dev.atrium.application.BookingFilter
import dev.atrium.application.BookingSort
import dev.atrium.application.BookingStatusCode
import dev.atrium.application.ListQuery
import dev.atrium.application.SortDirection
import jakarta.validation.constraints.Min
import java.time.Instant

class InvalidParamException(val field: String, val value: String) : RuntimeException("invalid value '$value' for $field")

/** Query-параметры списка: связываются из query по именам полей (@ModelAttribute по умолчанию). */
data class BookingListParams(
    val status: List<String> = emptyList(),
    val from: Instant? = null,
    val to: Instant? = null,
    val sort: String = "createdAt:desc",
    val cursor: String? = null,
    @field:Min(1) val limit: Int = 20,
) {
    fun toQuery(): ListQuery {
        val (field, dir) = sort.split(':', limit = 2).let { it[0] to (it.getOrNull(1) ?: "desc") }
        return ListQuery(
            filter = BookingFilter(
                statuses = status.map { raw ->
                    BookingStatusCode.entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: throw InvalidParamException("status", raw)
                }.toSet(),
                from = from,
                to = to,
            ),
            sort = when (field) {
                "createdAt" -> BookingSort.CREATED_AT
                "slotStart" -> BookingSort.SLOT_START
                else -> throw InvalidParamException("sort", field)
            },
            direction = if (dir.equals("asc", ignoreCase = true)) SortDirection.ASC else SortDirection.DESC,
            cursor = cursor,
            limit = limit,
        )
    }
}
