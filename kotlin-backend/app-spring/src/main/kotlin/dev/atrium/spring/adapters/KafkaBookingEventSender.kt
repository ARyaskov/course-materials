package dev.atrium.spring.adapters

import dev.atrium.infrastructure.events.BookingEventDto
import dev.atrium.infrastructure.events.BookingEventSender
import kotlinx.coroutines.future.await
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.stereotype.Component

@Component
class KafkaBookingEventSender(private val kafka: KafkaTemplate<String, BookingEventDto>) : BookingEventSender {
    override suspend fun send(event: BookingEventDto) {
        kafka.send("atrium.bookings", event.bookingId, event).await() // CompletableFuture → suspend
    }
}
