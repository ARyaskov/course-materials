package dev.atrium.spring.health

import dev.atrium.infrastructure.resilience.ResilientPaymentGateway
import io.github.resilience4j.circuitbreaker.CircuitBreaker
import org.springframework.boot.health.contributor.Health
import org.springframework.boot.health.contributor.HealthIndicator
import org.springframework.stereotype.Component

/** Не входит ни в liveness, ни в readiness: недоступность PayGate — не повод перезапускать или выводить инстанс из балансировки. */
@Component("paygate")
class PayGateHealthIndicator(private val gateway: ResilientPaymentGateway) : HealthIndicator {
    override fun health(): Health = when (val state = gateway.breakerState) {
        CircuitBreaker.State.CLOSED, CircuitBreaker.State.HALF_OPEN -> Health.up().withDetail("state", state.name).build()
        else -> Health.down().withDetail("state", state.name).build()
    }
}
