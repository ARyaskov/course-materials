package dev.atrium.ktor

import dev.atrium.application.ApplicationScope
import io.kotest.matchers.nulls.shouldBeNull
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.slf4j.MDCContext
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Test
import org.slf4j.MDC

/** MDC переживает смену dispatcher-а только с MDCContext в контексте корутины (урок 14.1). */
class MdcPropagationTest {
    @Test
    fun `mdc context survives withContext, plain launch loses it`() = runBlocking {
        MDC.put("requestId", "test-request-0001")
        val kept = withContext(MDCContext()) { withContext(Dispatchers.IO) { MDC.get("requestId") } }
        kept shouldBe "test-request-0001"

        val lost = async(Dispatchers.Default) { MDC.get("requestId") }.await()
        lost.shouldBeNull()
        MDC.clear()
    }

    @Test
    fun `application scope carries mdc of the launching thread`() = runBlocking {
        MDC.put("requestId", "bg-0001")
        val scope = ApplicationScope(onError = { throw it })
        val seen = scope.scope.async { withContext(Dispatchers.IO) { MDC.get("requestId") } }.await()
        seen shouldBe "bg-0001"
        MDC.clear()
    }
}
