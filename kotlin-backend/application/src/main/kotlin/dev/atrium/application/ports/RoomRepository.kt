package dev.atrium.application.ports

import dev.atrium.domain.Location
import dev.atrium.domain.LocationId
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId

interface RoomRepository {
    suspend fun find(id: RoomId): Room?
    suspend fun findByLocation(locationId: LocationId): List<Room>
    suspend fun findLocation(id: LocationId): Location?
}
