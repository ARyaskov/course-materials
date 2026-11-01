package dev.atrium.spring.api

import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import java.time.Instant

data class CreateBookingRequest(
    @field:NotBlank val roomId: String,
    val startsAt: Instant,
    @field:Min(15) @field:Max(480) val durationMinutes: Int = 60,
    @field:Size(max = 500) val comment: String? = null,
)

data class BookingResponse(
    val id: String,
    val roomId: String,
    val memberId: String,
    val startsAt: Instant,
    val endsAt: Instant,
    val status: String,
    val expiresAt: Instant? = null,
    val paymentId: String? = null,
    val createdAt: Instant,
)
