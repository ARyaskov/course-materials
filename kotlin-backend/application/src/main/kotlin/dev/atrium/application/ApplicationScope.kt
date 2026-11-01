package dev.atrium.application

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.slf4j.MDCContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Scope фоновых задач приложения: SupervisorJob — падение одной задачи не роняет остальные,
 * CoroutineExceptionHandler — ни одно исключение не теряется, shutdown() — graceful с таймаутом.
 */
class ApplicationScope(
    private val onError: (Throwable) -> Unit,
) : AutoCloseable {
    private val job = SupervisorJob()
    val scope: CoroutineScope = CoroutineScope(
        job + Dispatchers.Default + CoroutineName("atrium-background") + MDCContext() +
            CoroutineExceptionHandler { _, e -> onError(e) },
    )

    /** true — все фоновые корутины завершились в отведённое время; false — пришлось уходить, не дождавшись (урок 14.5). */
    suspend fun shutdown(grace: Duration = 10.seconds): Boolean {
        job.cancel(CancellationException("application shutdown"))
        val finished = withTimeoutOrNull(grace) { job.join() } != null
        if (!finished) onError(IllegalStateException("Background tasks did not finish in $grace"))
        return finished
    }

    override fun close() {
        job.cancel()
    }
}
