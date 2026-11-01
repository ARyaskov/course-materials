package dev.atrium.spring.api

import dev.atrium.application.OccupancyTracker
import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.RoomId
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.codec.ServerSentEvent
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.server.ResponseStatusException
import java.time.Instant
import kotlin.time.Duration.Companion.seconds

data class OccupancyEvent(val roomId: String, val busyUntil: Instant?)

/** SSE поверх Flow: MVC пишет элементы по мере появления; heartbeat держит соединение через прокси. */
@RestController
@RequestMapping("/api/v1/rooms")
class OccupancyController(private val tracker: OccupancyTracker, private val rooms: RoomRepository) {

    @GetMapping("/{id}/occupancy/stream", produces = [MediaType.TEXT_EVENT_STREAM_VALUE])
    suspend fun stream(@PathVariable id: String): Flow<ServerSentEvent<OccupancyEvent>> {
        val roomId = RoomId.parse(id) ?: throw ResponseStatusException(HttpStatus.BAD_REQUEST)
        rooms.find(roomId) ?: throw ResponseStatusException(HttpStatus.NOT_FOUND)
        val updates = tracker.forRoom(roomId).map { busyUntil ->
            ServerSentEvent.builder(OccupancyEvent(roomId.value.toString(), busyUntil)).event("occupancy").build()
        }
        val heartbeat = flow {
            while (true) {
                delay(15.seconds)
                emit(ServerSentEvent.builder<OccupancyEvent>().comment("keep-alive").build())
            }
        }
        return merge(updates, heartbeat)
    }
}
