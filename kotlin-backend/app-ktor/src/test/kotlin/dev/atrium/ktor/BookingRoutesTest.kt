package dev.atrium.ktor

import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.CreateBooking
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.testing.FakePaymentGateway
import dev.atrium.application.testing.FixedClock
import dev.atrium.application.testing.InMemoryBookingRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.application.testing.RecordingEventPublisher
import dev.atrium.application.testing.SequentialIds
import dev.atrium.domain.aLocation
import dev.atrium.ktor.api.BookingResponse
import dev.atrium.ktor.api.CreateBookingRequest
import dev.atrium.ktor.plugins.DevPrincipal
import dev.atrium.ktor.plugins.Problem
import dev.atrium.ktor.plugins.atriumJson
import dev.atrium.ktor.plugins.configureErrorPages
import dev.atrium.ktor.plugins.configureSerialization
import dev.atrium.ktor.routes.bookingRoutes
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.routing.routing
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.uuid.Uuid

class BookingRoutesTest {
    private val seeded = aLocation { room { name = "Осло" } }
    private val roomId = seeded.second.single().id.value.toString()
    private val memberId = Uuid.random().toString()

    private val bookings = InMemoryBookingRepository()
    private val rooms = InMemoryRoomRepository(seeded)
    private val events = RecordingEventPublisher()
    private val clock = FixedClock(Instant.parse("2026-10-01T09:00:00Z"))
    private val payments = FakePaymentGateway()
    private val createBooking = CreateBooking(bookings, rooms, events, SequentialIds(), clock)
    private val confirmBooking = ConfirmBooking(bookings, rooms, payments, events, clock)
    private val cancelBooking = CancelBooking(bookings, payments, events, clock)
    private val listBookings = ListMemberBookings(bookings)

    private fun ApplicationTestBuilder.routesUnderTest() {
        application {
            configureSerialization()
            configureErrorPages()
            install(DevPrincipal)
            routing { bookingRoutes(createBooking, confirmBooking, cancelBooking, listBookings) }
        }
    }

    @Test
    fun `creates booking and returns 201 with Location`() = testApplication {
        routesUnderTest()
        val client = createClient { install(ContentNegotiation) { json(atriumJson) } }

        val response = client.post("/api/v1/bookings") {
            contentType(ContentType.Application.Json)
            header("X-Member-Id", memberId)
            setBody(CreateBookingRequest(roomId = roomId, startsAt = "2026-10-01T10:00:00Z"))
        }

        assertEquals(HttpStatusCode.Created, response.status)
        assertTrue(response.headers["Location"]!!.startsWith("/api/v1/bookings/"))
        assertEquals("PENDING", response.body<BookingResponse>().status)
    }

    @Test
    fun `validation errors are accumulated`() = testApplication {
        routesUnderTest()
        val client = createClient { install(ContentNegotiation) { json(atriumJson) } }

        val response = client.post("/api/v1/bookings") {
            contentType(ContentType.Application.Json)
            header("X-Member-Id", memberId)
            setBody("""{"roomId": "", "startsAt": "not-a-date", "durationMinutes": 5}""")
        }

        assertEquals(HttpStatusCode.BadRequest, response.status)
        val problem = response.body<Problem>()
        assertEquals("https://atrium.dev/problems/validation", problem.type)
        assertEquals(setOf("roomId", "startsAt", "durationMinutes"), problem.errors!!.map { it.field }.toSet())
    }

    @Test
    fun `malformed json gives malformed problem`() = testApplication {
        routesUnderTest()
        val response = client.post("/api/v1/bookings") {
            contentType(ContentType.Application.Json)
            header("X-Member-Id", memberId)
            setBody("{not json")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertTrue(response.bodyAsText().contains("https://atrium.dev/problems/malformed"))
    }

    @Test
    fun `mine is not captured by id route`() = testApplication {
        routesUnderTest()
        val response = client.post("/api/v1/bookings/mine/confirm") { header("X-Member-Id", memberId) }
        // /mine/confirm сопоставляется с /{id}/confirm — id "mine" невалиден → 400; сам /mine — отдельный get
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }
}
