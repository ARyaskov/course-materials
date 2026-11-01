package dev.atrium.application.ports

import java.time.Instant

/** Источник времени как зависимость: в тестах подменяется FixedClock. */
fun interface Clock {
    fun now(): Instant
}
