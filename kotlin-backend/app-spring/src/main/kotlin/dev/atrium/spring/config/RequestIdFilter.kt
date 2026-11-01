package dev.atrium.spring.config

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.slf4j.MDC
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import kotlin.uuid.Uuid

/** X-Request-Id: принять от gateway или сгенерировать; вернуть в ответе; положить в MDC на время запроса (урок 14.1). */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class RequestIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
        val id = request.getHeader(HEADER)?.takeIf { it.length in 8..128 } ?: Uuid.random().toString()
        response.setHeader(HEADER, id)
        MDC.putCloseable("requestId", id).use { chain.doFilter(request, response) }
    }

    companion object {
        const val HEADER = "X-Request-Id"
    }
}
