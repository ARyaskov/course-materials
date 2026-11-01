package dev.atrium.spring.api

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT
import org.springframework.test.web.servlet.client.RestTestClient
import org.springframework.test.web.servlet.client.expectBody
import java.io.File

/** docs/openapi.yaml — артефакт: тест падает, если код изменил контракт, а файл не обновлён. */
@SpringBootTest(webEnvironment = RANDOM_PORT)
@AutoConfigureRestTestClient
class OpenApiContractTest(@Autowired private val client: RestTestClient) {

    @Test
    fun `committed spec matches generated`() {
        val generated = client.get().uri("/v3/api-docs.yaml").exchange().expectStatus().isOk.expectBody<String>().returnResult().responseBody!!
        val committed = File("../docs/openapi.yaml").readText()
        assertEquals(normalize(committed), normalize(generated), "docs/openapi.yaml is stale: run ./gradlew :app-spring:updateOpenApi")
    }

    private fun normalize(yaml: String): String = yaml.lines()
        .filterNot { it.trimStart().startsWith("servers") || it.trimStart().startsWith("- url:") }
        .joinToString("\n") { it.trimEnd() }
        .trim()
}
