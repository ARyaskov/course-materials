package dev.atrium.ktor.api

import dev.atrium.ktor.plugins.atriumJson
import kotlinx.serialization.MissingFieldException
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

class SerializationTest {
    @Test
    fun `unknown key is ignored and default applied`() {
        val request = atriumJson.decodeFromString<CreateBookingRequest>("""{"roomId": "r", "startsAt": "s", "attendees": 4}""")
        assertEquals(60, request.durationMinutes)
    }

    @Test
    fun `missing required field fails`() {
        assertFailsWith<MissingFieldException> { atriumJson.decodeFromString<CreateBookingRequest>("""{"startsAt": "s"}""") }
    }

    @Test
    fun `string in Int is not coerced`() {
        assertFailsWith<SerializationException> {
            atriumJson.decodeFromString<CreateBookingRequest>("""{"roomId": "r", "startsAt": "s", "durationMinutes": "60"}""")
        }
    }

    @Test
    fun `pending response omits paymentId`() {
        val json = atriumJson.encodeToString(
            BookingResponse("id", "room", "member", "2026-10-01T10:00:00Z", "2026-10-01T11:00:00Z", "PENDING", expiresAt = "2026-10-01T09:15:00Z", createdAt = "2026-10-01T09:00:00Z"),
        )
        assertFalse("paymentId" in json)
    }
}
