package dev.atrium.spring

import dev.atrium.application.ConfirmBooking
import dev.atrium.application.testing.FakePaymentGateway
import dev.atrium.application.testing.FixedClock
import dev.atrium.application.testing.InMemoryBookingRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.application.testing.RecordingEventPublisher
import dev.atrium.domain.aBooking
import dev.atrium.domain.aLocation
import dev.atrium.infrastructure.metrics.MicrometerMetrics
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.string.shouldNotMatch
import io.micrometer.core.instrument.simple.SimpleMeterRegistry
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.Instant

/** Имена метрик — контракт для алертов; теги не содержат UUID (урок 14.2). */
class MetricsNamesTest {
    private val registry = SimpleMeterRegistry()

    @Test
    fun `confirm flow registers the documented meters without high-cardinality tags`() = runTest {
        val seeded = aLocation()
        val bookings = InMemoryBookingRepository()
        val useCase = ConfirmBooking(bookings, InMemoryRoomRepository(seeded), FakePaymentGateway(), RecordingEventPublisher(), FixedClock(Instant.parse("2026-10-01T09:00:00Z")), MicrometerMetrics(registry))
        val pending = aBooking { roomId = seeded.second.single().id }.also { bookings.seed(it) }

        useCase.execute(pending.id, pending.memberId)

        registry.meters.map { it.id.name } shouldContainAll listOf("atrium.bookings.confirm.duration", "atrium.paygate.calls", "atrium.bookings.confirmed")
        registry.meters.flatMap { it.id.tags }.forEach { it.value shouldNotMatch Regex("[0-9a-f-]{36}") }
    }
}
