package dev.atrium.spring.api

import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class RoomResponse(
    val id: String,
    val locationId: String,
    val name: String,
    val capacity: Int,
    val pricePerHour: String,
    val amenities: List<String>,
)

internal fun Room.toResponse(): RoomResponse = RoomResponse(
    id = id.value.toString(),
    locationId = locationId.value.toString(),
    name = name,
    capacity = capacity,
    pricePerHour = pricePerHour.toString(),
    amenities = amenities.sorted(),
)

@RestController
@RequestMapping("/api/v1/rooms")
class RoomController(private val rooms: RoomRepository) {

    @GetMapping("/{id}")
    suspend fun get(@PathVariable id: String): ResponseEntity<RoomResponse> {
        val roomId = RoomId.parse(id) ?: return ResponseEntity.badRequest().build()
        val room = rooms.find(roomId) ?: return ResponseEntity.notFound().build()
        return ResponseEntity.ok(room.toResponse())
    }
}
