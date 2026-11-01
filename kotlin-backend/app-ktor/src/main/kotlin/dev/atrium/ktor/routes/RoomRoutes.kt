package dev.atrium.ktor.routes

import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.RoomId
import dev.atrium.ktor.api.toResponse
import io.ktor.http.HttpStatusCode
import io.ktor.server.request.requirePathParameter
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

fun Route.roomRoutes(rooms: RoomRepository) {
    route("/api/v1/rooms") {
        get("/{id}") {
            val id = RoomId.parse(call.requirePathParameter("id"))
                ?: return@get call.respond(HttpStatusCode.BadRequest)
            val room = rooms.find(id) ?: return@get call.respond(HttpStatusCode.NotFound)
            call.respond(room.toResponse())
        }
    }
}
