package dev.atrium.ktor

import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.domain.aLocation
import dev.atrium.ktor.api.RoomResponse
import dev.atrium.ktor.plugins.atriumJson
import dev.atrium.ktor.plugins.configureErrorPages
import dev.atrium.ktor.plugins.configureSerialization
import dev.atrium.ktor.routes.roomRoutes
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals

class RoomRoutesTest {
    private val seeded = aLocation { room { name = "Осло"; capacity = 4 } }
    private val rooms: RoomRepository = InMemoryRoomRepository(seeded)

    @Test
    fun `returns room by id`() = testApplication {
        application {
            configureSerialization()
            configureErrorPages()
            routing { roomRoutes(rooms) }
        }
        val client = createClient { install(ContentNegotiation) { json(atriumJson) } }

        val response = client.get("/api/v1/rooms/${seeded.second.single().id.value}")

        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals("Осло", response.body<RoomResponse>().name)
    }

    @Test
    fun `invalid id gives 400`() = testApplication {
        application { configureSerialization(); configureErrorPages(); routing { roomRoutes(rooms) } }
        assertEquals(HttpStatusCode.BadRequest, client.get("/api/v1/rooms/not-a-uuid").status)
    }

    @Test
    fun `unknown room gives 404`() = testApplication {
        application { configureSerialization(); configureErrorPages(); routing { roomRoutes(rooms) } }
        assertEquals(HttpStatusCode.NotFound, client.get("/api/v1/rooms/00000000-0000-0000-0000-000000000000").status)
    }
}
