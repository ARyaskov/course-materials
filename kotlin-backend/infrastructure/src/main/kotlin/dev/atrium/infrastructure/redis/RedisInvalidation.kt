package dev.atrium.infrastructure.redis

import dev.atrium.domain.RoomId
import io.lettuce.core.ExperimentalLettuceCoroutinesApi
import io.lettuce.core.RedisClient
import io.lettuce.core.api.coroutines
import io.lettuce.core.codec.StringCodec
import io.lettuce.core.pubsub.RedisPubSubAdapter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.future.await
import kotlinx.coroutines.launch

/** Pub/sub инвалидации: сообщение — идентификатор, TTL остаётся страховкой от пропущенных сообщений. */
@OptIn(ExperimentalLettuceCoroutinesApi::class)
class RedisInvalidation(private val client: RedisClient, scope: CoroutineScope, private val onRoomInvalidated: (RoomId) -> Unit) {
    private val pubsub = client.connectPubSub(StringCodec.UTF8)

    init {
        pubsub.addListener(object : RedisPubSubAdapter<String, String>() {
            override fun message(channel: String, message: String) {
                RoomId.parse(message)?.let(onRoomInvalidated)
            }
        })
        scope.launch { pubsub.async().subscribe(CHANNEL).await() }
    }

    suspend fun publishRoom(id: RoomId) {
        client.connect(StringCodec.UTF8).use { it.coroutines().publish(CHANNEL, id.value.toString()) }
    }

    private companion object {
        const val CHANNEL = "atrium:invalidate:room"
    }
}
