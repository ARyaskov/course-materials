package dev.atrium.infrastructure.redis

import io.lettuce.core.ScriptOutputType
import java.time.Duration
import java.time.Instant

/** Token bucket в Lua: атомарное пополнение и списание; общий лимит для всех инстансов. */
@OptIn(io.lettuce.core.ExperimentalLettuceCoroutinesApi::class)
class RedisRateLimiter(private val redis: AtriumRedis) {

    data class Decision(val allowed: Boolean, val remaining: Long, val retryAfter: Duration)

    suspend fun tryAcquire(key: String, capacity: Long, refillPerSecond: Double, now: Instant): Decision {
        val result = redis.commands.eval<List<Long>>(
            BUCKET_SCRIPT, ScriptOutputType.MULTI, arrayOf("atrium:rl:$key"),
            capacity.toString(), refillPerSecond.toString(), now.toEpochMilli().toString(),
        ) ?: return Decision(allowed = true, remaining = capacity, retryAfter = Duration.ZERO)
        val (allowed, remaining, waitMillis) = result
        return Decision(allowed == 1L, remaining, Duration.ofMillis(waitMillis))
    }

    private companion object {
        const val BUCKET_SCRIPT = """
            local capacity = tonumber(ARGV[1]); local refill = tonumber(ARGV[2]); local now = tonumber(ARGV[3])
            local bucket = redis.call('HMGET', KEYS[1], 'tokens', 'ts')
            local tokens = tonumber(bucket[1]) or capacity
            local ts = tonumber(bucket[2]) or now
            tokens = math.min(capacity, tokens + (now - ts) / 1000 * refill)
            local allowed = 0; local wait = 0
            if tokens >= 1 then tokens = tokens - 1; allowed = 1 else wait = math.ceil((1 - tokens) / refill * 1000) end
            redis.call('HSET', KEYS[1], 'tokens', tokens, 'ts', now)
            redis.call('PEXPIRE', KEYS[1], math.ceil(capacity / refill * 1000) * 2)
            return { allowed, math.floor(tokens), wait }
        """
    }
}
