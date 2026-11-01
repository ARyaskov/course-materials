package dev.atrium.application

import dev.atrium.application.ports.BookingEvent
import dev.atrium.application.ports.PaymentResult
import dev.atrium.application.testing.FakePaymentGateway
import dev.atrium.application.testing.FixedClock
import dev.atrium.application.testing.InMemoryBookingRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.application.testing.RecordingEventPublisher
import dev.atrium.domain.BookingError
import dev.atrium.domain.BookingStatus
import dev.atrium.domain.MemberId
import dev.atrium.domain.Money
import dev.atrium.domain.aBooking
import dev.atrium.domain.aLocation
import io.kotest.matchers.collections.shouldBeEmpty
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import java.time.Duration
import java.time.Instant
import kotlin.uuid.Uuid

class ConfirmBookingTest {
    private val now = Instant.parse("2026-10-01T09:00:00Z")
    private val clock = FixedClock(now)
    private val bookings = InMemoryBookingRepository()
    private val seeded = aLocation { room { pricePerHour = Money.rub("1200.00") } }
    private val rooms = InMemoryRoomRepository(seeded)
    private val payments = FakePaymentGateway()
    private val events = RecordingEventPublisher()
    private val useCase = ConfirmBooking(bookings, rooms, payments, events, clock)

    private val room = seeded.second.single()
    private val member = MemberId(Uuid.random())

    @Test
    fun `confirms pending booking and charges deposit for the slot`() = runTest {
        val pending = aBooking { roomId = room.id; memberId = member; slot(now + Duration.ofHours(1), Duration.ofMinutes(90)) }.also { bookings.seed(it) }

        val result = useCase.execute(pending.id, member)

        result.shouldBeInstanceOf<ConfirmResult.Confirmed>().booking.status.shouldBeInstanceOf<BookingStatus.Confirmed>()
        bookings.find(pending.id)!!.status.shouldBeInstanceOf<BookingStatus.Confirmed>()
        payments.charges.single().second shouldBe "confirm:${pending.id.value}"
        payments.lastAmount shouldBe Money.rub("1800.00") // 1200 × 1.5 часа
        events.published.single().shouldBeInstanceOf<BookingEvent.Confirmed>()
    }

    @Test
    fun `expired hold is rejected without charging`() = runTest {
        val expired = aBooking { roomId = room.id; memberId = member; status = BookingStatus.Pending(expiresAt = now - Duration.ofMinutes(1)) }.also { bookings.seed(it) }

        useCase.execute(expired.id, member).shouldBeInstanceOf<ConfirmResult.Rejected>().error.shouldBeInstanceOf<BookingError.HoldExpired>()

        payments.charges.shouldBeEmpty()
    }

    @Test
    fun `declined payment keeps booking pending`() = runTest {
        payments.nextCharge = { PaymentResult.Declined("insufficient funds") }
        val pending = aBooking { roomId = room.id; memberId = member }.also { bookings.seed(it) }

        useCase.execute(pending.id, member).shouldBeInstanceOf<ConfirmResult.Rejected>().error.shouldBeInstanceOf<BookingError.PaymentDeclined>()

        bookings.find(pending.id)!!.status.shouldBeInstanceOf<BookingStatus.Pending>()
    }
}
