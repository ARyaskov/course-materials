package dev.atrium.spring.api

import dev.atrium.domain.BookingError
import jakarta.servlet.http.HttpServletRequest
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus.BAD_REQUEST
import org.springframework.http.HttpStatus.CONFLICT
import org.springframework.http.HttpStatus.FORBIDDEN
import org.springframework.http.HttpStatus.GONE
import org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR
import org.springframework.http.HttpStatus.NOT_FOUND
import org.springframework.http.HttpStatus.PAYMENT_REQUIRED
import org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE
import org.springframework.http.HttpStatus.UNPROCESSABLE_CONTENT
import org.springframework.http.ProblemDetail
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.resource.NoResourceFoundException
import java.net.URI
import kotlin.uuid.Uuid

private const val PROBLEM_BASE = "https://atrium.dev/problems/"

data class FieldError(val field: String, val code: String, val message: String)

/** Единственное место, знающее одновременно BookingError и HTTP-статусы. Exhaustive when, без else. */
internal fun BookingError.toProblem(): ProblemDetail {
    val (status, type, detail) = when (this) {
        is BookingError.RoomNotFound -> Triple(NOT_FOUND, "room-not-found", "Room ${roomId.value} does not exist")
        is BookingError.BookingNotFound -> Triple(NOT_FOUND, "booking-not-found", "Booking ${bookingId.value} does not exist")
        is BookingError.NotOwner -> Triple(FORBIDDEN, "not-owner", "Booking ${bookingId.value} belongs to another member")
        is BookingError.SlotTaken -> Triple(CONFLICT, "slot-taken", "Room ${roomId.value} is booked from ${slot.start} to ${slot.end}")
        is BookingError.NotConfirmable, is BookingError.NotCancellable ->
            Triple(CONFLICT, "invalid-transition", "Operation is not applicable to the booking state")
        is BookingError.HoldExpired -> Triple(GONE, "hold-expired", "Hold for booking ${bookingId.value} has expired")
        BookingError.SlotInPast -> Triple(UNPROCESSABLE_CONTENT, "slot-in-past", "Slot start must be in the future")
        is BookingError.PaymentDeclined -> Triple(PAYMENT_REQUIRED, "payment-declined", reason)
        is BookingError.PaymentUnavailable -> Triple(SERVICE_UNAVAILABLE, "payment-unavailable", "Payment provider is unavailable, retry later")
        is BookingError.IdempotencyKeyReuse -> Triple(UNPROCESSABLE_CONTENT, "idempotency-key-reuse", "Idempotency-Key '$key' was used with a different request")
        is BookingError.RequestInProgress -> Triple(CONFLICT, "request-in-progress", "Request with Idempotency-Key '$key' is still in progress")
    }
    return ProblemDetail.forStatusAndDetail(status, detail).apply {
        this.type = URI.create(PROBLEM_BASE + type)
        title = type.replace('-', ' ').replaceFirstChar(Char::uppercase)
        if (this@toProblem is BookingError.SlotTaken) setProperty("roomId", roomId.value.toString())
        if (this@toProblem is BookingError.PaymentUnavailable) setProperty("retryAfter", 30)
    }
}

@RestControllerAdvice
class ApiErrorHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun onValidation(e: MethodArgumentNotValidException, request: HttpServletRequest): ProblemDetail =
        ProblemDetail.forStatus(BAD_REQUEST).apply {
            type = URI.create(PROBLEM_BASE + "validation")
            title = "Request validation failed"
            instance = URI.create(request.requestURI)
            setProperty(
                "errors",
                e.bindingResult.fieldErrors.map { FieldError(it.field, it.code ?: "invalid", it.defaultMessage ?: "") },
            )
        }

    @ExceptionHandler(HttpMessageNotReadableException::class)
    fun onMalformed(request: HttpServletRequest): ProblemDetail =
        ProblemDetail.forStatusAndDetail(BAD_REQUEST, "Request body cannot be parsed").apply {
            type = URI.create(PROBLEM_BASE + "malformed")
            title = "Malformed request"
            instance = URI.create(request.requestURI)
        }

    @ExceptionHandler(NoResourceFoundException::class)
    fun onNoResource(request: HttpServletRequest): ProblemDetail =
        ProblemDetail.forStatus(NOT_FOUND).apply {
            type = URI.create(PROBLEM_BASE + "not-found")
            title = "Not found"
            instance = URI.create(request.requestURI)
        }

    @ExceptionHandler(Exception::class)
    fun onUnexpected(e: Exception, request: HttpServletRequest): ProblemDetail {
        val errorId = Uuid.random().toString()
        log.error("Unhandled exception errorId={} path={}", errorId, request.requestURI, e)
        return ProblemDetail.forStatus(INTERNAL_SERVER_ERROR).apply {
            type = URI.create(PROBLEM_BASE + "internal")
            title = "Internal error"
            detail = "Unexpected error, reference $errorId"
            setProperty("errorId", errorId)
        }
    }
}

internal fun BookingError.toProblemResponse(): org.springframework.http.ResponseEntity<ProblemDetail> =
    org.springframework.http.ResponseEntity.of(toProblem()).build()
