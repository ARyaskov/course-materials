package dev.atrium.ktor.plugins

import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.request.requireQueryParameter
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ErrorPagesTest {
    @Test
    fun `unexpected exception gives 500 with errorId and without message`() = testApplication {
        application {
            configureSerialization(); configureErrorPages()
            routing { get("/boom") { error("boom") } }
        }
        val response = client.get("/boom")
        assertEquals(HttpStatusCode.InternalServerError, response.status)
        val body = response.bodyAsText()
        assertTrue("errorId" in body)
        assertFalse("boom" in body)
    }

    @Test
    fun `missing query parameter gives 400`() = testApplication {
        application {
            configureSerialization(); configureErrorPages()
            routing { get("/param") { call.respondText(call.requireQueryParameter("q")) } }
        }
        val response = client.get("/param")
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertTrue("Missing parameter: q" in response.bodyAsText())
    }

    @Test
    fun `unknown path gives problem 404`() = testApplication {
        application { configureSerialization(); configureErrorPages(); routing { } }
        val response = client.get("/nowhere")
        assertEquals(HttpStatusCode.NotFound, response.status)
        assertTrue("https://atrium.dev/problems/not-found" in response.bodyAsText())
    }
}
