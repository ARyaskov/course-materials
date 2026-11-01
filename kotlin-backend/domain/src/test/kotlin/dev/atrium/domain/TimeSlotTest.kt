package dev.atrium.domain

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.time.Duration
import java.time.Instant

class TimeSlotTest {
    private val at = Instant.parse("2026-10-01T10:00:00Z")

    @Test
    fun `rejects empty slot`() {
        val e = assertThrows<IllegalArgumentException> { TimeSlot(at, at) }
        assertTrue("end must be after start" in e.message!!)
    }

    @Test
    fun `rejects duration not aligned to 15 minutes`() {
        assertThrows<IllegalArgumentException> { TimeSlot.of(at, Duration.ofMinutes(20)) }
    }

    @Test
    fun `half-open interval does not overlap adjacent slot`() {
        val first = TimeSlot.of(at, Duration.ofHours(1))
        val second = TimeSlot.of(at + Duration.ofHours(1), Duration.ofHours(1))
        assertFalse(first overlaps second)
        assertTrue(first overlaps TimeSlot.of(at + Duration.ofMinutes(30), Duration.ofHours(1)))
    }

    @Test
    fun `contains is half-open`() {
        val slot = TimeSlot.of(at, Duration.ofHours(1))
        assertTrue(at in slot)
        assertFalse(slot.end in slot)
    }
}
