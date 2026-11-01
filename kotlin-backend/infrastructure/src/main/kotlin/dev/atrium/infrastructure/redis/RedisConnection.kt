package dev.atrium.infrastructure.redis

import io.lettuce.core.ExperimentalLettuceCoroutinesApi
import io.lettuce.core.RedisClient
import io.lettuce.core.RedisURI
import io.lettuce.core.api.StatefulRedisConnection
import io.lettuce.core.api.coroutines
import io.lettuce.core.api.coroutines.RedisCoroutinesCommands
import io.lettuce.core.codec.StringCodec
import java.time.Duration

/** Одно мультиплексируемое соединение Lettuce на приложение; корутинный API без блокировки потоков. */
@OptIn(ExperimentalLettuceCoroutinesApi::class)
class AtriumRedis(url: String) : AutoCloseable {
    val client: RedisClient = RedisClient.create(RedisURI.create(url).apply { timeout = Duration.ofMillis(500) })
    private val connection: StatefulRedisConnection<String, String> = client.connect(StringCodec.UTF8)

    val commands: RedisCoroutinesCommands<String, String> = connection.coroutines()

    override fun close() {
        connection.close()
        client.shutdown()
    }
}
