package dev.atrium.application

import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.LocationId
import dev.atrium.domain.RoomId
import dev.atrium.domain.TimeSlot
import java.time.Instant

sealed interface Availability {
    data object Free : Availability
    data class Busy(val until: Instant) : Availability
}

data class RoomAvailability(val roomId: RoomId, val availability: Availability)

/** Один запрос по всем комнатам локации (findActiveByRooms) вместо N+1 через async на каждую. */
class RoomAvailabilityQuery(
    private val roomRepository: RoomRepository,
    private val bookings: BookingRepository,
) {
    suspend fun availabilityFor(location: LocationId, slot: TimeSlot): List<RoomAvailability> {
        val rooms = roomRepository.findByLocation(location)
        val active = bookings.findActiveByRooms(rooms.map { it.id }, slot.start, slot.end)
        return rooms.map { room ->
            val overlapping = active[room.id].orEmpty().filter { it.slot overlaps slot }
            RoomAvailability(room.id, overlapping.maxOfOrNull { it.slot.end }?.let { Availability.Busy(it) } ?: Availability.Free)
        }
    }
}
