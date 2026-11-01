package dev.atrium.domain

import io.kotest.property.Arb
import io.kotest.property.arbitrary.Codepoint
import io.kotest.property.arbitrary.arbitrary
import io.kotest.property.arbitrary.az
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.string
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import kotlin.uuid.Uuid

/** Генераторы валидных объектов домена для property-тестов; невалидные данные — отдельными генераторами в тестах инвариантов. */
object Arbs {
    val dayStart: Instant = Instant.parse("2026-10-01T08:00:00Z")
    val dayEnd: Instant = Instant.parse("2026-10-01T22:00:00Z")

    fun timeSlot(from: Instant = dayStart, to: Instant = dayEnd): Arb<TimeSlot> = arbitrary {
        val quarters = Duration.between(from, to).toMinutes() / TimeSlot.SLOT_STEP_MINUTES
        val startQ = Arb.long(0 until quarters).bind()
        val lenQ = Arb.long(1..minOf(8, quarters - startQ)).bind()
        val start = from.plus(Duration.ofMinutes(startQ * TimeSlot.SLOT_STEP_MINUTES))
        TimeSlot.of(start, Duration.ofMinutes(lenQ * TimeSlot.SLOT_STEP_MINUTES))
    }

    fun money(): Arb<Money> = Arb.long(0..1_000_000L).map { Money(BigDecimal(it).movePointLeft(2), Money.RUB) }

    fun room(): Arb<Room> = Arb.bind(Arb.string(1..40, Codepoint.az()), Arb.int(1..200), money()) { name, capacity, price ->
        Room(RoomId(Uuid.random()), LocationId(Uuid.random()), name, capacity, price)
    }

    fun booking(): Arb<Booking> = Arb.bind(timeSlot(), Arb.element(statuses)) { slot, status ->
        aBooking { this.start = slot.start; this.duration = slot.duration; this.status = status }
    }

    private val statuses = listOf(BookingStatus.Pending(dayEnd), BookingStatus.Confirmed(PaymentId("p")), BookingStatus.Expired)
}
