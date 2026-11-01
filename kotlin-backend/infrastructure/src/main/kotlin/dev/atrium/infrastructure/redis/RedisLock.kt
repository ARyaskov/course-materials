package dev.atrium.infrastructure.redis

import io.lettuce.core.ScriptOutputType
import io.lettuce.core.SetArgs
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.time.Duration
import kotlin.uuid.Uuid

/** SET NX PX с токеном владельца; освобождение — Lua «удалить, если значение моё». Оптимизация, не гарантия корректности. */
@OptIn(io.lettuce.core.ExperimentalLettuceCoroutinesApi::class)
class RedisLock(private val redis: AtriumRedis) {

    suspend fun tryAcquire(key: String, ttl: Duration): String? {
        val token = Uuid.random().toString()
        val ok = redis.commands.set("atrium:lock:$key", token, SetArgs().nx().px(ttl.toMillis()))
        return if (ok == "OK") token else null
    }

    suspend fun release(key: String, token: String): Boolean =
        (redis.commands.eval<Long>(RELEASE_SCRIPT, ScriptOutputType.INTEGER, arrayOf("atrium:lock:$key"), token) ?: 0L) == 1L

    suspend fun <T> withLock(key: String, ttl: Duration, block: suspend () -> T): T? {
        val token = tryAcquire(key, ttl) ?: return null
        try {
            return block()
        } finally {
            withContext(NonCancellable) { release(key, token) }
        }
    }

    private companion object {
        const val RELEASE_SCRIPT = "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end"
    }
}
