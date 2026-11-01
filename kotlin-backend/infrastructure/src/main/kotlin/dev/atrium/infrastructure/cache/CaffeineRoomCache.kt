package dev.atrium.infrastructure.cache

import com.github.benmanes.caffeine.cache.AsyncLoadingCache
import com.github.benmanes.caffeine.cache.Caffeine
import com.github.benmanes.caffeine.cache.stats.CacheStats
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.future.await
import kotlinx.coroutines.future.future
import java.time.Duration

/** Caffeine поверх suspend-loader-а: single-flight, refreshAfterWrite без промаха на границе TTL, статистика. */
class CaffeineRoomCache(ttl: Duration, private val loader: suspend (RoomId) -> Room?, maxSize: Long = 10_000) {
    private val scope = CoroutineScope(Dispatchers.Default)
    private val rooms: AsyncLoadingCache<RoomId, Room?> = Caffeine.newBuilder()
        .maximumSize(maxSize)
        .expireAfterWrite(ttl)
        .refreshAfterWrite(ttl.dividedBy(2)) // фоновое обновление до истечения — без промаха на границе TTL
        .recordStats()
        .buildAsync { id, _ -> scope.future { loader(id) } }

    suspend fun get(id: RoomId): Room? = rooms.get(id).await()

    fun invalidate(id: RoomId) = rooms.synchronous().invalidate(id)

    fun stats(): CacheStats = rooms.synchronous().stats()
}
