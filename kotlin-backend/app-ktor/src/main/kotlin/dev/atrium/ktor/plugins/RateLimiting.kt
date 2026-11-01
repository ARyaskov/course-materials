package dev.atrium.ktor.plugins

import dev.atrium.application.ports.Clock
import dev.atrium.infrastructure.redis.RedisRateLimiter
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.createRouteScopedPlugin
import io.ktor.server.plugins.origin

class RedisRateLimitConfig {
    lateinit var limiter: RedisRateLimiter
    lateinit var clock: Clock
    var capacity: Long = 10
    var refillPerSecond: Double = 10.0 / 60
    var name: String = "bookings"
}

/** Общий лимит на все инстансы через Redis; встроенный RateLimit Ktor считает на инстанс. */
val RedisRateLimit = createRouteScopedPlugin("RedisRateLimit", ::RedisRateLimitConfig) {
    val config = pluginConfig
    onCall { call ->
        val key = call.memberPrincipal()?.memberId?.value?.toString() ?: call.request.origin.remoteAddress
        val decision = config.limiter.tryAcquire("${config.name}:$key", config.capacity, config.refillPerSecond, config.clock.now())
        call.response.headers.append("X-RateLimit-Remaining", decision.remaining.toString())
        if (!decision.allowed) {
            call.response.headers.append("Retry-After", decision.retryAfter.seconds.coerceAtLeast(1).toString())
            call.respondProblem(HttpStatusCode.TooManyRequests, "rate-limited", "Booking rate limit exceeded")
        }
    }
}
