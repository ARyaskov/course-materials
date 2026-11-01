package dev.atrium.application.ports

import dev.atrium.domain.RoomId
import java.time.LocalDate

data class UtilizationDelta(val roomId: RoomId, val day: LocalDate, val minutesBooked: Long)

interface UtilizationRepository {
    /** Идемпотентный upsert: повторный запуск backfill не удваивает минуты. */
    suspend fun upsertAll(deltas: List<UtilizationDelta>)
}
