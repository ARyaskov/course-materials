package dev.atrium.spring.api

import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.ConfirmResult
import dev.atrium.application.CreateBooking
import dev.atrium.application.CreateResult
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.fold
import dev.atrium.application.ports.IdempotencyKey
import org.springframework.web.bind.annotation.RequestHeader
import java.security.MessageDigest
import dev.atrium.application.ports.BookingRepository
import dev.atrium.domain.BookingError
import dev.atrium.domain.BookingId
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.net.URI

data class CancelBookingRequest(
    @field:NotBlank @field:Size(max = 200) val reason: String,
)

@RestController
@RequestMapping("/api/v1/bookings")
class BookingController(
    private val createBooking: CreateBooking,
    private val confirmBooking: ConfirmBooking,
    private val cancelBooking: CancelBooking,
    private val listMemberBookings: ListMemberBookings,
    private val bookings: BookingRepository,
) {
    @PostMapping
    suspend fun create(
        @Valid @RequestBody request: CreateBookingRequest,
        @RequestHeader("Idempotency-Key", required = false) idempotencyKey: String?,
        principal: MemberPrincipal,
    ): ResponseEntity<*> {
        val key = idempotencyKey?.let { IdempotencyKey(it, requestHash("POST", "/api/v1/bookings", request)) }
        return when (val result = createBooking.execute(request.toCommand(principal.memberId), key)) {
            is CreateResult.Created -> ResponseEntity
                .created(URI.create("/api/v1/bookings/${result.booking.id.value}"))
                .body(result.booking.toResponse())
            is CreateResult.Replayed -> ResponseEntity
                .created(URI.create("/api/v1/bookings/${result.booking.id.value}"))
                .body(result.booking.toResponse())
            is CreateResult.Rejected -> result.error.toProblemResponse()
        }
    }

    @GetMapping
    suspend fun list(
        principal: MemberPrincipal,
        @RequestParam cursor: String?,
        @RequestParam(defaultValue = "20") limit: Int,
    ): PageResponse<BookingResponse> = listMemberBookings.execute(principal.memberId, cursor, limit).let { page ->
        PageResponse(page.items.map { it.toResponse() }, page.nextCursor)
    }

    @GetMapping("/{id}")
    suspend fun get(@PathVariable id: String, principal: MemberPrincipal): ResponseEntity<*> {
        val bookingId = BookingId.parse(id) ?: return badId(id)
        val booking = bookings.find(bookingId) ?: return ResponseEntity.notFound().build<Any>()
        if (booking.memberId != principal.memberId) return BookingError.NotOwner(bookingId, principal.memberId).toProblemResponse()
        return ResponseEntity.ok(booking.toResponse())
    }

    @PostMapping("/{id}/confirm")
    suspend fun confirm(@PathVariable id: String, principal: MemberPrincipal): ResponseEntity<*> {
        val bookingId = BookingId.parse(id) ?: return badId(id)
        return when (val result = confirmBooking.execute(bookingId, principal.memberId)) {
            is ConfirmResult.Confirmed -> ResponseEntity.ok(result.booking.toResponse())
            is ConfirmResult.AlreadyConfirmed -> ResponseEntity.ok(result.booking.toResponse())
            is ConfirmResult.Rejected -> result.error.toProblemResponse()
        }
    }

    @PostMapping("/{id}/cancel")
    suspend fun cancel(
        @PathVariable id: String,
        @Valid @RequestBody request: CancelBookingRequest,
        principal: MemberPrincipal,
    ): ResponseEntity<*> =
        cancelBooking.execute(BookingId.parse(id) ?: return badId(id), principal.memberId, request.reason)
            .fold({ ResponseEntity.ok(it.toResponse()) }, { it.toProblemResponse() })

    private fun badId(raw: String): ResponseEntity<ProblemDetail> = ResponseEntity
        .of(ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "id must be a UUID, was '$raw'"))
        .build()
}

data class PageResponse<T>(val items: List<T>, val nextCursor: String?)

/** sha256(method + path + тело): тот же ключ с другим телом → Mismatch → 422. */
internal fun requestHash(method: String, path: String, body: Any): String =
    MessageDigest.getInstance("SHA-256").digest("$method $path ${body.hashCode()}".toByteArray()).joinToString("") { "%02x".format(it) }
