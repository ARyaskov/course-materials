package dev.atrium.infrastructure.postgres

import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.Location
import dev.atrium.domain.LocationId
import dev.atrium.domain.Money
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import dev.atrium.infrastructure.json.atriumJsonMapper
import kotlinx.coroutines.CoroutineDispatcher
import java.sql.ResultSet
import java.time.ZoneId
import java.util.Currency
import java.util.UUID
import javax.sql.DataSource
import kotlin.uuid.toJavaUuid
import kotlin.uuid.toKotlinUuid

class JdbcRoomRepository(
    private val dataSource: DataSource,
    private val dbDispatcher: CoroutineDispatcher,
) : RoomRepository {

    override suspend fun find(id: RoomId): Room? = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("$SELECT WHERE id = ?").use { statement ->
            statement.setObject(1, id.value.toJavaUuid())
            statement.executeQuery().use { rs -> if (rs.next()) rs.toRoom() else null }
        }
    }

    override suspend fun findByLocation(locationId: LocationId): List<Room> = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("$SELECT WHERE location_id = ? ORDER BY name").use { statement ->
            statement.setObject(1, locationId.value.toJavaUuid())
            statement.executeQuery().use { rs -> buildList { while (rs.next()) add(rs.toRoom()) } }
        }
    }

    override suspend fun findLocation(id: LocationId): Location? = dataSource.withConnection(dbDispatcher) { connection ->
        connection.prepareStatement("SELECT id, name, time_zone FROM locations WHERE id = ?").use { statement ->
            statement.setObject(1, id.value.toJavaUuid())
            statement.executeQuery().use { rs ->
                if (rs.next()) Location(LocationId(rs.getObject("id", UUID::class.java).toKotlinUuid()), rs.getString("name"), ZoneId.of(rs.getString("time_zone"))) else null
            }
        }
    }

    private fun ResultSet.toRoom(): Room = Room(
        id = RoomId(getObject("id", UUID::class.java).toKotlinUuid()),
        locationId = LocationId(getObject("location_id", UUID::class.java).toKotlinUuid()),
        name = getString("name"),
        capacity = getInt("capacity"),
        pricePerHour = Money(getBigDecimal("price_per_hour"), Currency.getInstance(getString("currency").trim())),
        amenities = atriumJsonMapper.readValue(getString("amenities"), Array<String>::class.java).toSet(),
    )

    private companion object {
        const val SELECT = "SELECT id, location_id, name, capacity, price_per_hour, currency, amenities::text AS amenities FROM rooms"
    }
}
