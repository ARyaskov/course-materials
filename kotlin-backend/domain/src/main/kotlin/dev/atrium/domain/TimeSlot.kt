package dev.atrium.domain

import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Полуоткрытый интервал [start, end): бронь с 10:00 до 11:00 не пересекается с бронью с 11:00.
 * Инварианты проверяются в init — экземпляр с end <= start существовать не может.
 */
data class TimeSlot(val start: Instant, val end: Instant) : Comparable<TimeSlot> {
    init {
        require(end > start) { "TimeSlot end must be after start: start=$start, end=$end" }
        require(start.truncatedTo(ChronoUnit.MINUTES) == start) { "TimeSlot start must be aligned to a minute: $start" }
        require(Duration.between(start, end).toMinutes() % SLOT_STEP_MINUTES == 0L) {
            "TimeSlot duration must be a multiple of $SLOT_STEP_MINUTES minutes: ${Duration.between(start, end)}"
        }
    }

    val duration: Duration get() = Duration.between(start, end)

    infix fun overlaps(other: TimeSlot): Boolean = start < other.end && other.start < end

    operator fun contains(instant: Instant): Boolean = instant >= start && instant < end

    override fun compareTo(other: TimeSlot): Int = compareValuesBy(this, other, TimeSlot::start, TimeSlot::end)

    companion object {
        const val SLOT_STEP_MINUTES = 15L

        fun of(start: Instant, duration: Duration): TimeSlot = TimeSlot(start, start.plus(duration))
    }
}
