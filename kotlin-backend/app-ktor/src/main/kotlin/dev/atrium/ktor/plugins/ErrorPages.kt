package dev.atrium.ktor.plugins

import dev.atrium.domain.BookingError
import dev.atrium.ktor.api.FieldError
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.MissingRequestParameterException
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.path
import io.ktor.server.response.respond
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlin.uuid.Uuid

private const val PROBLEM_BASE = "https://atrium.dev/problems/"

@Serializable
data class Problem(
    val type: String,
    val title: String,
    val status: Int,
    val detail: String? = null,
    val instance: String? = null,
    val errors: List<FieldError>? = null,
    val errorId: String? = null,
)

fun problem(status: HttpStatusCode, type: String, detail: String?, instance: String? = null, errors: List<FieldError>? = null, errorId: String? = null) =
    Problem(PROBLEM_BASE + type, type.replace('-', ' ').replaceFirstChar(Char::uppercase), status.value, detail, instance, errors, errorId)

/** Та же таблица «ошибка → статус», что и в app-spring ApiErrorHandler. */
fun BookingError.toProblem(instance: String): Pair<HttpStatusCode, Problem> = when (this) {
    is BookingError.RoomNotFound -> HttpStatusCode.NotFound to problem(HttpStatusCode.NotFound, "room-not-found", "Room ${roomId.value} does not exist", instance)
    is BookingError.BookingNotFound -> HttpStatusCode.NotFound to problem(HttpStatusCode.NotFound, "booking-not-found", "Booking ${bookingId.value} does not exist", instance)
    is BookingError.NotOwner -> HttpStatusCode.Forbidden to problem(HttpStatusCode.Forbidden, "not-owner", "Booking ${bookingId.value} belongs to another member", instance)
    is BookingError.SlotTaken -> HttpStatusCode.Conflict to problem(HttpStatusCode.Conflict, "slot-taken", "Room ${roomId.value} is booked from ${slot.start} to ${slot.end}", instance)
    is BookingError.NotConfirmable, is BookingError.NotCancellable ->
        HttpStatusCode.Conflict to problem(HttpStatusCode.Conflict, "invalid-transition", "Operation is not applicable to the booking state", instance)
    is BookingError.HoldExpired -> HttpStatusCode.Gone to problem(HttpStatusCode.Gone, "hold-expired", "Hold for booking ${bookingId.value} has expired", instance)
    BookingError.SlotInPast -> HttpStatusCode.UnprocessableEntity to problem(HttpStatusCode.UnprocessableEntity, "slot-in-past", "Slot start must be in the future", instance)
    is BookingError.PaymentDeclined -> HttpStatusCode.PaymentRequired to problem(HttpStatusCode.PaymentRequired, "payment-declined", reason, instance)
    is BookingError.PaymentUnavailable -> HttpStatusCode.ServiceUnavailable to problem(HttpStatusCode.ServiceUnavailable, "payment-unavailable", "Payment provider is unavailable, retry later", instance)
    is BookingError.IdempotencyKeyReuse -> HttpStatusCode.UnprocessableEntity to problem(HttpStatusCode.UnprocessableEntity, "idempotency-key-reuse", "Idempotency-Key '$key' was used with a different request", instance)
    is BookingError.RequestInProgress -> HttpStatusCode.Conflict to problem(HttpStatusCode.Conflict, "request-in-progress", "Request with Idempotency-Key '$key' is still in progress", instance)
}

suspend fun ApplicationCall.respondProblem(
    status: HttpStatusCode,
    type: String,
    detail: String?,
    errors: List<FieldError>? = null,
    errorId: String? = null,
) = respond(status, problem(status, type, detail, request.path(), errors, errorId))

suspend fun ApplicationCall.respondError(error: BookingError) {
    val (status, body) = error.toProblem(request.path())
    if (error is BookingError.PaymentUnavailable) response.headers.append("Retry-After", "30")
    respond(status, body)
}

fun Application.configureErrorPages() {
    install(StatusPages) {
        exception<MissingRequestParameterException> { call, e ->
            call.respondProblem(HttpStatusCode.BadRequest, "validation", "Missing parameter: ${e.parameterName}")
        }
        exception<BadRequestException> { call, e ->
            val detail = (e.cause as? SerializationException)?.message?.substringBefore("\n") ?: "Request body cannot be parsed"
            call.respondProblem(HttpStatusCode.BadRequest, "malformed", detail)
        }
        exception<SerializationException> { call, _ ->
            call.respondProblem(HttpStatusCode.BadRequest, "malformed", "Request body cannot be parsed")
        }
        status(HttpStatusCode.NotFound) { call, status ->
            call.respondProblem(status, "not-found", null)
        }
        status(HttpStatusCode.MethodNotAllowed) { call, status ->
            call.respondProblem(status, "method-not-allowed", null)
        }
        exception<Throwable> { call, cause ->
            val errorId = Uuid.random().toString()
            call.application.log.error("Unhandled exception errorId=$errorId requestId=${call.requestId} path=${call.request.path()}", cause)
            call.respondProblem(HttpStatusCode.InternalServerError, "internal", "Unexpected error, reference $errorId", errorId = errorId)
        }
    }
}
