package dev.atrium.domain

import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import java.time.Instant

class BookingTest {
    private val paymentId = PaymentId("pay_1")

    @Nested
    inner class Confirm {
        @Test
        fun `pending booking becomes confirmed with payment id`() {
            val confirmed = aBooking().confirm(paymentId)
            confirmed.status.shouldBeInstanceOf<BookingStatus.Confirmed>().paymentId shouldBe paymentId
        }

        @Test
        fun `confirming cancelled booking is a programmer error`() {
            val cancelled = aBooking().cancel("user", Instant.parse("2026-09-30T10:00:00Z"))
            assertThrows<IllegalStateException> { assertNotNull(cancelled.confirm(paymentId)) }
        }
    }

    @ParameterizedTest
    @MethodSource("inactiveStatuses")
    fun `inactive statuses cannot be cancelled`(status: BookingStatus) {
        assertThrows<IllegalStateException> { assertNotNull(aBooking { this.status = status }.cancel("x", Instant.EPOCH)) }
    }

    companion object {
        @JvmStatic
        fun inactiveStatuses() = listOf(BookingStatus.Expired, BookingStatus.NoShow, BookingStatus.Cancelled("y", Instant.EPOCH))
    }
}
