package dev.atrium.spring

import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.read.ListAppender
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.testing.FakePaymentGateway
import dev.atrium.application.testing.FixedClock
import dev.atrium.application.testing.InMemoryBookingRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.application.testing.RecordingEventPublisher
import dev.atrium.domain.aBooking
import dev.atrium.domain.aLocation
import io.kotest.matchers.collections.shouldNotBeEmpty
import io.kotest.matchers.string.shouldNotContain
import io.kotest.matchers.string.shouldNotMatch
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import org.slf4j.LoggerFactory

/** Сценарий confirm не должен писать PII ни в сообщения, ни в структурные поля (урок 14.1). */
class LogPiiTest {
    @Test
    fun `confirm logs contain no email or card numbers`() = runTest {
        val logger = LoggerFactory.getLogger("dev.atrium") as Logger
        val appender = ListAppender<ILoggingEvent>().also { it.start(); logger.addAppender(it) }
        try {
            val seeded = aLocation()
            val bookings = InMemoryBookingRepository()
            val useCase = ConfirmBooking(bookings, InMemoryRoomRepository(seeded), FakePaymentGateway(), RecordingEventPublisher(), FixedClock(java.time.Instant.parse("2026-10-01T09:00:00Z")))
            val pending = aBooking { roomId = seeded.second.single().id }.also { bookings.seed(it) }

            useCase.execute(pending.id, pending.memberId)

            val lines = appender.list.map { it.formattedMessage + (it.keyValuePairs ?: emptyList()).joinToString() }
            lines.shouldNotBeEmpty()
            lines.forEach { line ->
                line shouldNotContain "@example.org"
                line shouldNotMatch Regex(".*\\d{16}.*")
            }
        } finally {
            logger.detachAppender(appender)
        }
    }
}
