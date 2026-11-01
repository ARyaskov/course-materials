package dev.atrium.application

import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.BookingRepository
import dev.atrium.domain.Booking
import dev.atrium.domain.BookingId
import dev.atrium.domain.MemberId
import java.time.Instant
import java.util.Base64
import kotlin.uuid.Uuid

/** Keyset-пагинация по (createdAt, id); курсор — непрозрачная base64-строка. Невалидный курсор — пустая страница. */
class ListMemberBookings(private val bookings: BookingRepository) {
    suspend fun execute(memberId: MemberId, cursor: String?, limit: Int): Page<Booking> {
        val size = limit.coerceIn(1, MAX_LIMIT)
        val decoded = cursor?.let { decode(it) ?: return Page.empty() }
        val items = bookings.findByMember(memberId, decoded, size)
        val next = items.takeIf { it.size == size }?.last()?.let { encode(BookingCursor(it.createdAt, it.id)) }
        return Page(items, next)
    }

    private fun encode(cursor: BookingCursor): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString("${cursor.createdAt}|${cursor.id.value}".toByteArray())

    private fun decode(raw: String): BookingCursor? = runCatching {
        val (createdAt, id) = String(Base64.getUrlDecoder().decode(raw)).split('|', limit = 2)
        BookingCursor(Instant.parse(createdAt), BookingId(Uuid.parse(id)))
    }.getOrNull()

    private companion object {
        const val MAX_LIMIT = 100
    }
}
