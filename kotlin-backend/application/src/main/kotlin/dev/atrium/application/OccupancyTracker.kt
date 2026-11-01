package dev.atrium.application

import dev.atrium.domain.RoomId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import java.time.Instant

/** Текущая занятость комнат как StateFlow: один источник, много подписчиков (табло через SSE). */
class OccupancyTracker {
    val occupancy: StateFlow<Map<RoomId, Instant>>
        field = MutableStateFlow(emptyMap())

    fun markBusy(roomId: RoomId, until: Instant) {
        occupancy.update { it + (roomId to until) }
    }

    fun markFree(roomId: RoomId) {
        occupancy.update { it - roomId }
    }

    fun forRoom(roomId: RoomId): Flow<Instant?> = occupancy.map { it[roomId] }.distinctUntilChanged()
}
