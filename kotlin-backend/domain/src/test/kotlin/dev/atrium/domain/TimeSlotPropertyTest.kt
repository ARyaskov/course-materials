package dev.atrium.domain

import io.kotest.matchers.collections.shouldBeSortedBy
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.list
import io.kotest.property.checkAll
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class TimeSlotPropertyTest {
    @Test
    fun `overlaps is symmetric`() = runTest {
        checkAll(Arbs.timeSlot(), Arbs.timeSlot()) { a, b -> (a overlaps b) shouldBe (b overlaps a) }
    }

    @Test
    fun `slot overlaps itself and adjacent slot does not`() = runTest {
        checkAll(Arbs.timeSlot(Arbs.dayStart, Arbs.dayEnd.minusSeconds(3600 * 3))) { slot ->
            (slot overlaps slot) shouldBe true
            val adjacent = TimeSlot.of(slot.end, slot.duration)
            (slot overlaps adjacent) shouldBe false
        }
    }

    @Test
    fun `free windows never overlap occupied slots`() = runTest {
        checkAll(Arb.list(Arbs.timeSlot(), 0..10)) { occupied ->
            val windows = occupied.freeWindows(Arbs.dayStart, Arbs.dayEnd)
            windows.forEach { w -> occupied.none { it overlaps w } shouldBe true }
            windows.shouldBeSortedBy { it.start }
        }
    }
}
