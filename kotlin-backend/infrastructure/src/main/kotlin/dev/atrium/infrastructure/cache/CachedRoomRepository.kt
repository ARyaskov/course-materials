package dev.atrium.infrastructure.cache

import com.github.benmanes.caffeine.cache.AsyncLoadingCache
import com.github.benmanes.caffeine.cache.Caffeine
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.RoomRepository
import dev.atrium.domain.Location
import dev.atrium.domain.LocationId
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.future.await
import kotlinx.coroutines.future.future
import java.time.Duration

/** Декоратор через делегирование: Caffeine для точечных чтений и списка локации; занятость не кэшируется никогда. */
class CachedRoomRepository(
    private val delegate: RoomRepository,
    @Suppress("unused") private val clock: Clock,
    ttl: Duration = Duration.ofMinutes(10),
) : RoomRepository by delegate {

    private val scope = CoroutineScope(Dispatchers.Default)
    private val rooms = CaffeineRoomCache(ttl, loader = { delegate.find(it) })
    private val locations: AsyncLoadingCache<LocationId, Location?> = Caffeine.newBuilder().expireAfterWrite(ttl).recordStats()
        .buildAsync { id, _ -> scope.future { delegate.findLocation(id) } }
    private val byLocation: AsyncLoadingCache<LocationId, List<Room>> = Caffeine.newBuilder().expireAfterWrite(Duration.ofMinutes(1)).recordStats()
        .buildAsync { id, _ -> scope.future { delegate.findByLocation(id) } }

    override suspend fun find(id: RoomId): Room? = rooms.get(id)

    override suspend fun findLocation(id: LocationId): Location? = locations.get(id).await()

    override suspend fun findByLocation(locationId: LocationId): List<Room> = byLocation.get(locationId).await()

    fun invalidate(id: RoomId, locationId: LocationId) {
        rooms.invalidate(id)
        byLocation.synchronous().invalidate(locationId)
    }
}
