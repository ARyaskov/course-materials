package dev.atrium.spring.api

import dev.atrium.application.CreateBooking
import dev.atrium.application.ports.BookingRepository
import dev.atrium.application.ports.Clock
import dev.atrium.application.ports.EventPublisher
import dev.atrium.application.ports.IdGenerator
import dev.atrium.application.ports.RoomRepository
import dev.atrium.application.testing.FixedClock
import dev.atrium.application.testing.InMemoryBookingRepository
import dev.atrium.application.testing.InMemoryRoomRepository
import dev.atrium.application.testing.RecordingEventPublisher
import dev.atrium.application.testing.SequentialIds
import dev.atrium.domain.MemberId
import dev.atrium.domain.aLocation
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.TestConfiguration
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.post
import org.springframework.web.method.support.HandlerMethodArgumentResolver
import java.time.Instant
import kotlin.uuid.Uuid

@WebMvcTest(BookingController::class)
@Import(BookingControllerTest.Fakes::class)
class BookingControllerTest(@Autowired private val mockMvc: MockMvc) {

    companion object {
        // Одна локация с одной комнатой для всех тестов класса — id известен заранее
        val seeded = aLocation { room { name = "Осло" } }
        val roomId: String = seeded.second.single().id.value.toString()
    }

    @TestConfiguration
    class Fakes {
        @Bean fun bookings(): BookingRepository = InMemoryBookingRepository()
        @Bean fun rooms(): RoomRepository = InMemoryRoomRepository(seeded)
        @Bean fun clock(): Clock = FixedClock(Instant.parse("2026-10-01T09:00:00Z"))
        @Bean fun events(): EventPublisher = RecordingEventPublisher()
        @Bean fun ids(): IdGenerator = SequentialIds()
        @Bean fun createBooking(b: BookingRepository, r: RoomRepository, e: EventPublisher, i: IdGenerator, c: Clock) = CreateBooking(b, r, e, i, c)
        @Bean fun principalResolver(): HandlerMethodArgumentResolver = FixedPrincipalResolver(MemberId(Uuid.random()))
    }

    @Test
    fun `creates booking and returns 201 with Location`() {
        mockMvc.post("/api/v1/bookings") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"roomId": "$roomId", "startsAt": "2026-10-01T10:00:00Z", "durationMinutes": 60}"""
        }.asyncDispatch().andExpect {
            status { isCreated() }
            header { exists("Location") }
            jsonPath("$.status") { value("PENDING") }
            jsonPath("$.expiresAt") { value("2026-10-01T09:15:00Z") }
        }
    }

    @Test
    fun `rejects slot in the past with 422 problem`() {
        mockMvc.post("/api/v1/bookings") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"roomId": "$roomId", "startsAt": "2026-09-01T10:00:00Z"}"""
        }.asyncDispatch().andExpect {
            status { isUnprocessableContent() }
            content { contentType(MediaType.APPLICATION_PROBLEM_JSON) }
            jsonPath("$.type") { value("https://atrium.dev/problems/slot-in-past") }
        }
    }
}
