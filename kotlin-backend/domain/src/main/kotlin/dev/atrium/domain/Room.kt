package dev.atrium.domain

import java.time.Duration

data class Location(
    val id: LocationId,
    val name: String,
    val timeZone: java.time.ZoneId,
)

data class Room(
    val id: RoomId,
    val locationId: LocationId,
    val name: String,
    val capacity: Int,
    val pricePerHour: Money,
    val amenities: Set<String> = emptySet(),
) {
    init {
        require(name.isNotBlank()) { "Room name must not be blank" }
        require(capacity in 1..MAX_CAPACITY) { "Room capacity must be in 1..$MAX_CAPACITY: $capacity" }
    }

    /** Депозит за бронь — стоимость слота по часовой ставке, пропорционально длительности. */
    fun depositFor(slot: TimeSlot): Money =
        pricePerHour * java.math.BigDecimal(slot.duration.toMinutes()).divide(java.math.BigDecimal(Duration.ofHours(1).toMinutes()))

    companion object {
        const val MAX_CAPACITY = 200
    }
}
