package dev.atrium.application

import dev.atrium.domain.BookingId
import java.time.Instant
import java.util.Base64
import kotlin.uuid.Uuid

enum class BookingStatusCode { PENDING, CONFIRMED, CANCELLED, EXPIRED, NO_SHOW }

/** Белый список сортировок — тип, а не строка: до SQL доходит только column из перечисления. */
enum class BookingSort(val column: String) { CREATED_AT("created_at"), SLOT_START("lower(slot)") }

enum class SortDirection { ASC, DESC }

data class BookingFilter(
    val statuses: Set<BookingStatusCode> = emptySet(),
    val from: Instant? = null,
    val to: Instant? = null,
) {
    init {
        require(from == null || to == null || from <= to) { "from must not be after to" }
    }
}

data class ListQuery(
    val filter: BookingFilter = BookingFilter(),
    val sort: BookingSort = BookingSort.CREATED_AT,
    val direction: SortDirection = SortDirection.DESC,
    val cursor: String? = null,
    val limit: Int = 20,
) {
    val effectiveLimit: Int get() = limit.coerceIn(1, MAX_LIMIT)

    companion object {
        const val MAX_LIMIT = 100
    }
}

/** Курсор несёт имя и направление сортировки: курсор от одной сортировки не применится к другой. */
data class Cursor(val sort: BookingSort, val direction: SortDirection, val value: String, val id: BookingId) {
    fun encode(): String = Base64.getUrlEncoder().withoutPadding().encodeToString("${sort.name}|${direction.name}|$value|${id.value}".toByteArray())

    companion object {
        fun decode(raw: String, expectedSort: BookingSort, expectedDirection: SortDirection): Cursor? = runCatching {
            val (sort, direction, value, id) = String(Base64.getUrlDecoder().decode(raw)).split('|', limit = 4)
            Cursor(BookingSort.valueOf(sort), SortDirection.valueOf(direction), value, BookingId(Uuid.parse(id)))
        }.getOrNull()?.takeIf { it.sort == expectedSort && it.direction == expectedDirection }
    }
}
