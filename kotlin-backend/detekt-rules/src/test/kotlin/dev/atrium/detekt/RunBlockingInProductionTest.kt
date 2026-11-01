package dev.atrium.detekt

import io.gitlab.arturbosch.detekt.test.lint
import io.kotest.matchers.collections.shouldBeEmpty
import io.kotest.matchers.collections.shouldHaveSize
import org.junit.jupiter.api.Test

class RunBlockingInProductionTest {
    @Test
    fun `runBlocking in a regular function is reported`() {
        val code = """
            import kotlinx.coroutines.runBlocking
            fun handle() { runBlocking { } }
        """.trimIndent()
        RunBlockingInProduction().lint(code) shouldHaveSize 1
    }

    @Test
    fun `runBlocking in main and Blocking adapters is allowed`() {
        val code = """
            import kotlinx.coroutines.runBlocking
            fun main() { runBlocking { } }
            fun createBlocking() { runBlocking { } }
        """.trimIndent()
        RunBlockingInProduction().lint(code).shouldBeEmpty()
    }
}
