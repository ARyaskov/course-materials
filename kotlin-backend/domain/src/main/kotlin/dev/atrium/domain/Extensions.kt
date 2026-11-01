package dev.atrium.domain

import java.time.Instant
import java.time.temporal.ChronoUnit

fun Instant.truncatedToMinutes(): Instant = truncatedTo(ChronoUnit.MINUTES)

/** Брони, занимающие комнату в данный момент: только активные и с попаданием момента в слот. */
fun List<Booking>.activeAt(instant: Instant): List<Booking> = filter { it.isActive && instant in it.slot }

/** Занятые слоты комнаты за день, отсортированные по началу — основа для расчёта свободных окон. */
fun List<Booking>.occupiedSlots(): List<TimeSlot> = filter { it.isActive }.map { it.slot }.sorted()

/** Свободные окна между занятыми слотами внутри рабочего дня [dayStart, dayEnd). */
fun List<TimeSlot>.freeWindows(dayStart: Instant, dayEnd: Instant): List<TimeSlot> {
    var cursor = dayStart
    val windows = mutableListOf<TimeSlot>()
    for (slot in sorted()) {
        if (slot.start > cursor) windows += TimeSlot(cursor, slot.start)
        if (slot.end > cursor) cursor = slot.end
    }
    if (dayEnd > cursor) windows += TimeSlot(cursor, dayEnd)
    return windows
}
