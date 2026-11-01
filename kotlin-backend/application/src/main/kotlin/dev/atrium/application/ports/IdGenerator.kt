package dev.atrium.application.ports

import dev.atrium.domain.BookingId

/** Генерация идентификаторов как зависимость: в тестах — последовательные, в production — Uuid v7. */
fun interface IdGenerator {
    fun nextBookingId(): BookingId
}
