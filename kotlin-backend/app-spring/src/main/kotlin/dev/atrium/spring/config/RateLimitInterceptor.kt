package dev.atrium.spring.config

import dev.atrium.application.ports.Clock
import dev.atrium.infrastructure.redis.RedisRateLimiter
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import kotlinx.coroutines.runBlocking
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ProblemDetail
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken
import org.springframework.stereotype.Component
import org.springframework.web.servlet.HandlerInterceptor
import org.springframework.web.servlet.config.annotation.InterceptorRegistry
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer
import tools.jackson.databind.json.JsonMapper
import java.net.URI

/** Лимит на создание броней по участнику: runBlocking на виртуальном потоке Tomcat до входа в корутину контроллера. */
@Component
class RateLimitInterceptor(private val limiter: RedisRateLimiter, private val clock: Clock, private val jsonMapper: JsonMapper) : HandlerInterceptor {
    override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
        if (request.method != "POST" || !request.requestURI.startsWith("/api/v1/bookings")) return true
        val subject = (SecurityContextHolder.getContext().authentication as? JwtAuthenticationToken)?.token?.subject ?: return true
        val decision = runBlocking { limiter.tryAcquire("bookings:$subject", capacity = 10, refillPerSecond = 10.0 / 60, now = clock.now()) }
        response.setHeader("X-RateLimit-Remaining", decision.remaining.toString())
        if (decision.allowed) return true
        response.status = 429
        response.setHeader("Retry-After", decision.retryAfter.seconds.coerceAtLeast(1).toString())
        response.contentType = MediaType.APPLICATION_PROBLEM_JSON_VALUE
        val problem = ProblemDetail.forStatusAndDetail(HttpStatus.TOO_MANY_REQUESTS, "Booking rate limit exceeded").apply {
            type = URI.create("https://atrium.dev/problems/rate-limited")
            title = "Rate limited"
        }
        response.writer.write(jsonMapper.writeValueAsString(problem))
        return false
    }
}

@org.springframework.context.annotation.Configuration
class RateLimitConfig(private val interceptor: RateLimitInterceptor) : WebMvcConfigurer {
    override fun addInterceptors(registry: InterceptorRegistry) {
        registry.addInterceptor(interceptor).addPathPatterns("/api/v1/bookings")
    }
}
