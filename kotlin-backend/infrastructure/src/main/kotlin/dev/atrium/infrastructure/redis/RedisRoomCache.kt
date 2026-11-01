package dev.atrium.infrastructure.redis

import com.github.benmanes.caffeine.cache.Caffeine
import dev.atrium.application.runCatchingCancellable
import dev.atrium.domain.LocationId
import dev.atrium.domain.Money
import dev.atrium.domain.Room
import dev.atrium.domain.RoomId
import dev.atrium.infrastructure.json.atriumJsonMapper
import dev.atrium.infrastructure.json.read
import io.lettuce.core.SetArgs
import io.micrometer.core.instrument.MeterRegistry
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.math.BigDecimal
import java.time.Duration
import java.util.Currency
import kotlin.random.Random
import kotlin.uuid.Uuid

/** Формат хранения в Redis — собственный контракт с версией в ключе: смена полей → новый префикс. */
data class RoomDto(val id: String, val locationId: String, val name: String, val capacity: Int, val price: String, val currency: String, val amenities: List<String>, val schemaVersion: Int = 1) {
    fun toDomain() = Room(RoomId(Uuid.parse(id)), LocationId(Uuid.parse(locationId)), name, capacity, Money(BigDecimal(price), Currency.getInstance(currency)), amenities.toSet())
}

fun Room.toDto() = RoomDto(id.value.toString(), locationId.value.toString(), name, capacity, pricePerHour.amount.toPlainString(), pricePerHour.currency.currencyCode, amenities.sorted())

/** Cache-aside с single-flight внутри инстанса, джиттером TTL и fallback на loader при недоступном Redis. */
@OptIn(io.lettuce.core.ExperimentalLettuceCoroutinesApi::class)
class RedisRoomCache(
    private val redis: AtriumRedis,
    private val ttl: Duration,
    private val loader: suspend (RoomId) -> Room?,
    registry: MeterRegistry,
) {
    private val errors = registry.counter("atrium.redis.errors", "cache", "rooms")
    private val inflight = Caffeine.newBuilder().expireAfterWrite(Duration.ofSeconds(10)).build<RoomId, Mutex>()

    suspend fun get(id: RoomId): Room? {
        val key = "atrium:room:v1:${id.value}"
        cached(key)?.let { return it }
        return inflight.get(id) { Mutex() }.withLock {
            cached(key)?.let { return it }
            val room = loader(id) ?: return null
            val jitter = Duration.ofSeconds(Random.nextLong(0, 60))
            runCatchingCancellable { redis.commands.set(key, atriumJsonMapper.writeValueAsString(room.toDto()), SetArgs().px(ttl.plus(jitter).toMillis())) }
                .onFailure { errors.increment() }
            room
        }
    }

    suspend fun invalidate(id: RoomId) {
        runCatchingCancellable { redis.commands.del("atrium:room:v1:${id.value}") }.onFailure { errors.increment() }
    }

    private suspend fun cached(key: String): Room? =
        runCatchingCancellable { redis.commands.get(key) }.getOrElse { errors.increment(); null }?.let { atriumJsonMapper.read<RoomDto>(it).toDomain() }
}
