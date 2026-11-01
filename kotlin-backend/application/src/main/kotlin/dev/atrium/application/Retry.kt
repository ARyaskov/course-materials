package dev.atrium.application

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.time.Duration

/**
 * Учебный retry для идемпотентных вызовов. Production-вариант с backoff, jitter и circuit breaker —
 * Resilience4j в infrastructure (глава 12). CancellationException никогда не повторяется.
 */
suspend fun <T> withRetry(
    attempts: Int,
    delayBetween: Duration,
    retryOn: (Throwable) -> Boolean = { true },
    block: suspend () -> T,
): T {
    var lastError: Throwable? = null
    repeat(attempts) { attempt ->
        try {
            return block()
        } catch (e: Throwable) {
            if (e is CancellationException || !retryOn(e)) throw e
            lastError = e
            if (attempt < attempts - 1) delay(delayBetween)
        }
    }
    throw checkNotNull(lastError)
}
