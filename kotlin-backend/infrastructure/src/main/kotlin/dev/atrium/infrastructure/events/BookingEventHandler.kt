package dev.atrium.infrastructure.events

import dev.atrium.application.OccupancyTracker
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Notification
import dev.atrium.domain.BookingId
import io.micrometer.core.instrument.MeterRegistry
import kotlin.uuid.Uuid

/** Общий обработчик для Spring-listener-а и Ktor-цикла: транзакция снаружи, эффекты — записи в базу. */
class BookingEventHandler(
    private val processed: ProcessedEventRepository,
    private val notificationOutbox: NotificationOutboxRepository,
    private val bookings: BookingRepository,
    private val tracker: OccupancyTracker,
    metrics: MeterRegistry,
) {
    private val duplicates = metrics.counter("atrium.events.duplicates")

    suspend fun handle(event: BookingEventDto) {
        if (!processed.markProcessed(Uuid.parse(event.eventId), consumer = CONSUMER)) {
            duplicates.increment()
            return
        }
        val bookingId = BookingId(Uuid.parse(event.bookingId))
        when (event) {
            is BookingEventDto.Confirmed -> bookings.find(bookingId)?.let { booking ->
                notificationOutbox.enqueue(Notification(id = Uuid.parse(event.eventId), memberId = booking.memberId, bookingId = bookingId, template = "booking-confirmed"))
                tracker.markBusy(booking.roomId, booking.slot.end)
            }
            is BookingEventDto.Cancelled, is BookingEventDto.Expired -> bookings.find(bookingId)?.let { tracker.markFree(it.roomId) }
            is BookingEventDto.Created -> Unit
        }
    }

    private companion object {
        const val CONSUMER = "atrium-notify"
    }
}
