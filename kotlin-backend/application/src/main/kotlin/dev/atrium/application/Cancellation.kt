package dev.atrium.application

import kotlinx.coroutines.CancellationException

/** runCatching для корутин: отмена не перехватывается и продолжает распространяться. */
inline fun <T> runCatchingCancellable(block: () -> T): Result<T> = try {
    Result.success(block())
} catch (e: CancellationException) {
    throw e
} catch (e: Throwable) {
    Result.failure(e)
}
