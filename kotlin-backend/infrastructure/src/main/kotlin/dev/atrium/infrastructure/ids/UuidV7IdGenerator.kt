package dev.atrium.infrastructure.ids

import dev.atrium.application.ports.IdGenerator
import dev.atrium.domain.BookingId
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * Uuid.generateV7 — experimental в Kotlin 2.4 (см. docs/decisions.md, запись ADR-003).
 * Opt-in локализован в этом файле; при стабилизации — убрать аннотацию.
 */
@OptIn(ExperimentalUuidApi::class)
object UuidV7IdGenerator : IdGenerator {
    override fun nextBookingId(): BookingId = BookingId(Uuid.generateV7())
}
