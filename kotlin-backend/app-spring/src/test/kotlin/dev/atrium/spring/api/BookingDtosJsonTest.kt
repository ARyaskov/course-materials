package dev.atrium.spring.api

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.jackson.test.autoconfigure.JsonTest
import org.springframework.boot.test.json.JacksonTester
import tools.jackson.databind.exc.MismatchedInputException
import java.time.Instant
import kotlin.uuid.Uuid

@JsonTest
class BookingDtosJsonTest(
    @Autowired private val json: JacksonTester<CreateBookingRequest>,
    @Autowired private val responses: JacksonTester<BookingResponse>,
) {
    @Test
    fun `missing durationMinutes falls back to default`() {
        val parsed = json.parseObject("""{"roomId": "7f3a", "startsAt": "2026-10-01T10:00:00Z"}""")
        assertEquals(60, parsed.durationMinutes)
    }

    @Test
    fun `unknown property is ignored`() {
        val parsed = json.parseObject("""{"roomId": "7f3a", "startsAt": "2026-10-01T10:00:00Z", "attendees": 4}""")
        assertEquals("7f3a", parsed.roomId)
    }

    @Test
    fun `explicit null in non-null Int is rejected`() {
        assertThrows<MismatchedInputException> {
            json.parseObject("""{"roomId": "7f3a", "startsAt": "2026-10-01T10:00:00Z", "durationMinutes": null}""")
        }
    }

    @Test
    fun `pending response omits paymentId key`() {
        val response = BookingResponse(
            id = Uuid.random().toString(), roomId = Uuid.random().toString(), memberId = Uuid.random().toString(),
            startsAt = Instant.parse("2026-10-01T10:00:00Z"), endsAt = Instant.parse("2026-10-01T11:00:00Z"),
            status = "PENDING", expiresAt = Instant.parse("2026-10-01T09:15:00Z"), createdAt = Instant.parse("2026-10-01T09:00:00Z"),
        )
        val written = responses.write(response).json
        assertFalse("paymentId" in written)
        assertEquals(true, "\"expiresAt\":\"2026-10-01T09:15:00Z\"" in written)
    }
}
