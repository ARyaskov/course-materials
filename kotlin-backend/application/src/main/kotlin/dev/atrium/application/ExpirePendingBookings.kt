package dev.atrium.application

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.EventPublisher
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import java.time.Instant

/** Фоновая задача истечения холдов: батчами, с проверкой отмены между элементами. */
class ExpirePendingBookings(
    private val bookings: BookingRepository,
    private val events: EventPublisher,
) {
    suspend fun expireBatch(now: Instant, batchSize: Int = 100): Int {
        val expired = bookings.findPendingExpiredBefore(now, batchSize)
        var count = 0
        for (booking in expired) {
            currentCoroutineContext().ensureActive() // остановка между элементами, не посреди сохранения
            bookings.save(booking.expire())
            events.publish(BookingEvent.Expired(booking.id, now))
            count++
        }
        return count
    }
}
