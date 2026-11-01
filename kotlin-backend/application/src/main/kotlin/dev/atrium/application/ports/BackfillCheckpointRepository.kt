package dev.atrium.application.ports

import java.time.Instant

data class BackfillCheckpoint(val runId: String, val cursor: BookingCursor?, val processed: Long, val completedAt: Instant?)

interface BackfillCheckpointRepository {
    suspend fun find(runId: String): BackfillCheckpoint?
    /** В той же транзакции, что и upsert чанка: checkpoint никогда не опережает данные. */
    suspend fun save(runId: String, cursor: BookingCursor, processed: Long)
    suspend fun complete(runId: String, at: Instant)
}
