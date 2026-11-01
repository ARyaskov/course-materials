package dev.atrium.domain

import java.time.ZoneId
import kotlin.uuid.Uuid

@AtriumDsl
class RoomBuilder(private val locationId: LocationId) {
    var id: RoomId = RoomId(Uuid.random())
    var name: String = "Room"
    var capacity: Int = 6
    var pricePerHour: Money = Money.rub("1000.00")
    private val amenities = mutableSetOf<String>()

    fun amenities(vararg names: String) { amenities += names }

    fun build(): Room = Room(id, locationId, name, capacity, pricePerHour, amenities.toSet())
}

@AtriumDsl
class LocationBuilder {
    var id: LocationId = LocationId(Uuid.random())
    var name: String = "Location"
    var timeZone: ZoneId = ZoneId.of("Europe/Moscow")
    private val rooms = mutableListOf<Room>()

    fun room(configure: RoomBuilder.() -> Unit = {}): Room =
        RoomBuilder(id).apply(configure).build().also { rooms += it }

    fun build(): Pair<Location, List<Room>> = Location(id, name, timeZone) to rooms.toList()
}

fun aLocation(configure: LocationBuilder.() -> Unit = {}): Pair<Location, List<Room>> =
    LocationBuilder().apply(configure).build()
