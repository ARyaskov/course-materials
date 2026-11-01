package dev.atrium.ktor

import dev.atrium.application.ApplicationScope
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Test
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.time.Duration.Companion.seconds

/** Остановка ждёт завершения итерации под NonCancellable: в журнале нет открытых итераций (урок 14.5). */
class ShutdownTest {
    @Test
    fun `shutdown waits for the current iteration`() = runBlocking {
        val journal = ConcurrentLinkedQueue<String>()
        val scope = ApplicationScope(onError = { throw it })
        scope.scope.launch {
            while (isActive) {
                journal += "start"
                withContext(NonCancellable) { delay(200); journal += "end" }
            }
        }
        delay(50)
        val finished = scope.shutdown(grace = 5.seconds)

        finished shouldBe true
        journal.count { it == "start" } shouldBe journal.count { it == "end" }
    }
}
