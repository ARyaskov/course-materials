package dev.atrium.infrastructure.resilience

import dev.atrium.application.ports.PaymentGateway
import dev.atrium.application.ports.PaymentResult
import dev.atrium.domain.BookingId
import dev.atrium.domain.Money
import dev.atrium.domain.PaymentId
import io.github.resilience4j.bulkhead.Bulkhead
import io.github.resilience4j.bulkhead.BulkheadConfig
import io.github.resilience4j.bulkhead.BulkheadFullException
import io.github.resilience4j.circuitbreaker.CallNotPermittedException
import io.github.resilience4j.circuitbreaker.CircuitBreaker
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry
import io.github.resilience4j.core.IntervalFunction
import io.github.resilience4j.kotlin.bulkhead.executeSuspendFunction
import io.github.resilience4j.kotlin.circuitbreaker.executeSuspendFunction
import io.github.resilience4j.kotlin.retry.executeSuspendFunction
import io.github.resilience4j.kotlin.timelimiter.executeSuspendFunction
import io.github.resilience4j.micrometer.tagged.TaggedCircuitBreakerMetrics
import io.github.resilience4j.micrometer.tagged.TaggedRetryMetrics
import io.github.resilience4j.retry.RetryConfig
import io.github.resilience4j.retry.RetryRegistry
import io.github.resilience4j.timelimiter.TimeLimiter
import io.github.resilience4j.timelimiter.TimeLimiterConfig
import io.micrometer.core.instrument.MeterRegistry
import kotlinx.coroutines.TimeoutCancellationException
import java.time.Duration

/**
 * Декоратор поверх любого PaymentGateway. Порядок: bulkhead → circuit breaker → retry → time limiter → вызов.
 * Отказы — значения PaymentResult.Unavailable; Declined — ответ провайдера, не отказ.
 */
class ResilientPaymentGateway(
    private val delegate: PaymentGateway,
    registry: MeterRegistry,
    timeout: Duration = Duration.ofSeconds(5),
    maxAttempts: Int = 2,
) : PaymentGateway {

    /** Для PayGateHealthIndicator: состояние показывается в деталях health, но не влияет на readiness (урок 15.2). */
    val breakerState: CircuitBreaker.State get() = circuitBreaker.state

    private val circuitBreakerRegistry = CircuitBreakerRegistry.ofDefaults()
    private val retryRegistry = RetryRegistry.ofDefaults()

    private val circuitBreaker = circuitBreakerRegistry.circuitBreaker(
        "paygate",
        CircuitBreakerConfig.custom()
            .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED).slidingWindowSize(20)
            .failureRateThreshold(50f)
            .slowCallDurationThreshold(Duration.ofSeconds(3)).slowCallRateThreshold(50f)
            .waitDurationInOpenState(Duration.ofSeconds(30))
            .permittedNumberOfCallsInHalfOpenState(3)
            .recordResult { it is PaymentResult.Unavailable }
            .build(),
    )

    private val retry = retryRegistry.retry(
        "paygate",
        RetryConfig.custom<PaymentResult>()
            .maxAttempts(maxAttempts)
            .intervalFunction(IntervalFunction.ofExponentialRandomBackoff(Duration.ofMillis(200), 2.0, 0.3))
            .retryOnResult { it is PaymentResult.Unavailable }
            .build(),
    )

    private val timeLimiter = TimeLimiter.of(TimeLimiterConfig.custom().timeoutDuration(timeout).build())
    private val bulkhead = Bulkhead.of("paygate", BulkheadConfig.custom().maxConcurrentCalls(25).maxWaitDuration(Duration.ofMillis(100)).build())

    init {
        TaggedCircuitBreakerMetrics.ofCircuitBreakerRegistry(circuitBreakerRegistry).bindTo(registry)
        TaggedRetryMetrics.ofRetryRegistry(retryRegistry).bindTo(registry)
    }

    override suspend fun charge(bookingId: BookingId, amount: Money, idempotencyKey: String): PaymentResult =
        guarded { delegate.charge(bookingId, amount, idempotencyKey) }

    override suspend fun refund(paymentId: PaymentId): PaymentResult = guarded { delegate.refund(paymentId) }

    private suspend fun guarded(call: suspend () -> PaymentResult): PaymentResult = try {
        bulkhead.executeSuspendFunction {
            circuitBreaker.executeSuspendFunction {
                retry.executeSuspendFunction {
                    timeLimiter.executeSuspendFunction { call() }
                }
            }
        }
    } catch (e: CallNotPermittedException) {
        PaymentResult.Unavailable("circuit open")
    } catch (e: BulkheadFullException) {
        PaymentResult.Unavailable("too many concurrent payment calls")
    } catch (e: TimeoutCancellationException) {
        PaymentResult.Unavailable("timeout")
    }
}
