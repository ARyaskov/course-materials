package dev.atrium.application

import dev.atrium.application.ports.BackfillCheckpointRepository
import dev.atrium.application.ports.BookingCursor
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.TransactionRunner
import dev.atrium.application.ports.UtilizationDelta
import dev.atrium.application.ports.UtilizationRepository
import dev.atrium.domain.BookingStatus
import kotlinx.coroutines.delay
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.chunked
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import java.time.Instant
import java.time.ZoneOffset
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

data class BackfillSummary(val runId: String, val processed: Long)

/** Пересчёт загрузки комнат: поток батчами по курсору, checkpoint в транзакции с upsert-ом, дроссель между чанками. */
class RoomUtilizationBackfill(
    private val bookings: BookingRepository,
    private val utilization: UtilizationRepository,
    private val checkpoints: BackfillCheckpointRepository,
    private val transactions: TransactionRunner,
    private val clock: Clock,
) {
    @OptIn(ExperimentalCoroutinesApi::class)
    suspend fun run(runId: String, from: Instant, to: Instant, batchSize: Int = 500, pause: Duration = 50.milliseconds): BackfillSummary {
        val existing = checkpoints.find(runId)
        if (existing?.completedAt != null) return BackfillSummary(runId, existing.processed)
        var processed = existing?.processed ?: 0L

        bookings.streamCreatedBetween(from, to, batchSize, after = existing?.cursor)
            .filter { it.status is BookingStatus.Confirmed || it.status is BookingStatus.NoShow }
            .map { UtilizationDelta(it.roomId, it.slot.start.atOffset(ZoneOffset.UTC).toLocalDate(), it.slot.duration.toMinutes()) to BookingCursor(it.createdAt, it.id) }
            .chunked(200)
            .onEach { chunk ->
                transactions.transactional {
                    utilization.upsertAll(chunk.map { it.first })
                    processed += chunk.size
                    checkpoints.save(runId, chunk.last().second, processed)
                }
                delay(pause)
            }
            .collect()

        checkpoints.complete(runId, clock.now())
        return BackfillSummary(runId, processed)
    }
}
