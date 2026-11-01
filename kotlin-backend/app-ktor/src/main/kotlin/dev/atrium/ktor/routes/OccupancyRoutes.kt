package dev.atrium.ktor.routes

import dev.atrium.application.OccupancyTracker
import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.RoomId
import dev.atrium.ktor.plugins.atriumJson
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.sse.ServerSentEvent
import io.ktor.server.sse.heartbeat
import io.ktor.server.sse.sse
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlin.time.Duration.Companion.seconds

@Serializable
data class OccupancyEvent(val roomId: String, val busyUntil: String? = null)

/** SSE: collect держит соединение до отключения клиента; отмена снимает подписку на StateFlow. */
fun Route.occupancyRoutes(tracker: OccupancyTracker, rooms: RoomRepository) {
    sse("/api/v1/rooms/{id}/occupancy/stream") {
        val roomId = call.parameters["id"]?.let(RoomId::parse) ?: return@sse call.respond(HttpStatusCode.BadRequest)
        rooms.find(roomId) ?: return@sse call.respond(HttpStatusCode.NotFound)

        heartbeat {
            period = 15.seconds
            event = ServerSentEvent(comments = "keep-alive")
        }

        tracker.forRoom(roomId).collect { busyUntil ->
            send(ServerSentEvent(data = atriumJson.encodeToString(OccupancyEvent(roomId.value.toString(), busyUntil?.toString())), event = "occupancy"))
        }
    }
}
