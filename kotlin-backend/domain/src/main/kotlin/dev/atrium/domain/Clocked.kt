package dev.atrium.domain

import java.time.Instant

fun interface TimeSource {
    fun now(): Instant
}

context(time: TimeSource)
fun Booking.isHoldExpired(): Boolean = (status as? BookingStatus.Pending)?.let { it.expiresAt < time.now() } ?: false

context(time: TimeSource)
fun TimeSlot.isInPast(): Boolean = start < time.now()
