package dev.atrium.ktor.config

import io.kotest.matchers.collections.shouldBeEmpty
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.string.shouldContain
import io.ktor.server.config.MapApplicationConfig
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/** validate() отвергает невалидные наборы и пропускает рабочий (урок 14.4). */
class AtriumConfigTest {
    private fun config(vararg overrides: Pair<String, String>) = MapApplicationConfig(
        "atrium.database.url" to "jdbc:postgresql://localhost/atrium", "atrium.database.user" to "a", "atrium.database.password" to "a",
        "atrium.paygate.baseUrl" to "http://localhost:8090", "atrium.paygate.apiKey" to "k",
        "atrium.notify.baseUrl" to "http://localhost:8091", "atrium.notify.apiKey" to "k",
        *overrides,
    ).atrium()

    @Test
    fun `valid configuration passes`() {
        config().validate(env = "dev").shouldBeEmpty()
    }

    @ParameterizedTest
    @CsvSource(
        "atrium.database.poolSize, 500, poolSize",
        "atrium.paygate.apiKey, '', apiKey is blank",
        "atrium.paygate.baseUrl, https://paygate.example.com, outside prod",
    )
    fun `invalid values are reported`(key: String, value: String, expected: String) {
        config(key to value).validate(env = "dev").joinToString() shouldContain expected
    }

    @Test
    fun `dev placeholder key is rejected in prod`() {
        config("atrium.paygate.apiKey" to "dev-key").validate(env = "prod") shouldContain "atrium.paygate.apiKey is the dev placeholder in prod"
    }
}
