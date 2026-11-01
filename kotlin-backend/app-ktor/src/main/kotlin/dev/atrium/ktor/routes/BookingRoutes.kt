package dev.atrium.ktor.routes

import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.ConfirmResult
import dev.atrium.application.CreateBooking
import dev.atrium.application.CreateResult
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.fold
import dev.atrium.application.ports.IdempotencyKey
import io.ktor.server.request.header
import java.security.MessageDigest
import dev.atrium.domain.BookingId
import dev.atrium.ktor.api.CancelBookingRequest
import dev.atrium.ktor.api.CreateBookingRequest
import dev.atrium.ktor.api.PageResponse
import dev.atrium.ktor.api.toCommand
import dev.atrium.ktor.api.toResponse
import dev.atrium.ktor.api.validate
import dev.atrium.ktor.plugins.memberPrincipal
import dev.atrium.ktor.plugins.respondError
import dev.atrium.ktor.plugins.respondProblem
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.request.receive
import io.ktor.server.request.requirePathParameter
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.RoutingContext
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route

/** Оглавление API броней: обработчики длиннее 10 строк вынесены в функции с receiver RoutingContext. */
fun Route.bookingRoutes(
    createBooking: CreateBooking,
    confirmBooking: ConfirmBooking,
    cancelBooking: CancelBooking,
    listBookings: ListMemberBookings,
) {
    route("/api/v1/bookings") {
        get {
            val principal = call.memberPrincipal() ?: return@get call.respond(HttpStatusCode.Unauthorized)
            val cursor = call.queryParameters["cursor"]
            val limit = call.queryParameters["limit"]?.toIntOrNull() ?: 20
            val page = listBookings.execute(principal.memberId, cursor, limit)
            call.respond(PageResponse(page.items.map { it.toResponse() }, page.nextCursor))
        }
        get("/mine") {
            val principal = call.memberPrincipal() ?: return@get call.respond(HttpStatusCode.Unauthorized)
            val page = listBookings.execute(principal.memberId, call.queryParameters["cursor"], call.queryParameters["limit"]?.toIntOrNull() ?: 20)
            call.respond(PageResponse(page.items.map { it.toResponse() }, page.nextCursor))
        }
        post { handleCreate(createBooking) }
        post("/{id}/confirm") { handleConfirm(confirmBooking) }
        post("/{id}/cancel") { handleCancel(cancelBooking) }
    }
}

private suspend fun RoutingContext.handleCreate(createBooking: CreateBooking) {
    val principal = call.memberPrincipal() ?: return call.respond(HttpStatusCode.Unauthorized)
    val request = call.receive<CreateBookingRequest>()
    val errors = request.validate()
    if (errors.isNotEmpty()) return call.respondProblem(HttpStatusCode.BadRequest, "validation", "Request validation failed", errors = errors)
    val key = call.request.header("Idempotency-Key")?.let { IdempotencyKey(it, requestHash("POST", "/api/v1/bookings", request)) }
    when (val result = createBooking.execute(request.toCommand(principal.memberId), key)) {
        is CreateResult.Created, is CreateResult.Replayed -> {
            val booking = (result as? CreateResult.Created)?.booking ?: (result as CreateResult.Replayed).booking
            call.response.header(HttpHeaders.Location, "/api/v1/bookings/${booking.id.value}")
            call.respond(HttpStatusCode.Created, booking.toResponse())
        }
        is CreateResult.Rejected -> call.respondError(result.error)
    }
}

private suspend fun RoutingContext.handleConfirm(confirmBooking: ConfirmBooking) {
    val bookingId = BookingId.parse(call.requirePathParameter("id"))
        ?: return call.respondProblem(HttpStatusCode.BadRequest, "validation", "id must be a UUID")
    val principal = call.memberPrincipal() ?: return call.respond(HttpStatusCode.Unauthorized)
    when (val result = confirmBooking.execute(bookingId, principal.memberId)) {
        is ConfirmResult.Confirmed -> call.respond(HttpStatusCode.OK, result.booking.toResponse())
        is ConfirmResult.AlreadyConfirmed -> call.respond(HttpStatusCode.OK, result.booking.toResponse())
        is ConfirmResult.Rejected -> call.respondError(result.error)
    }
}

private suspend fun RoutingContext.handleCancel(cancelBooking: CancelBooking) {
    val bookingId = BookingId.parse(call.requirePathParameter("id"))
        ?: return call.respondProblem(HttpStatusCode.BadRequest, "validation", "id must be a UUID")
    val principal = call.memberPrincipal() ?: return call.respond(HttpStatusCode.Unauthorized)
    val request = call.receive<CancelBookingRequest>()
    if (request.reason.isBlank() || request.reason.length > 200) {
        return call.respondProblem(HttpStatusCode.BadRequest, "validation", "reason must be 1..200 chars")
    }
    cancelBooking.execute(bookingId, principal.memberId, request.reason)
        .fold({ call.respond(HttpStatusCode.OK, it.toResponse()) }, { call.respondError(it) })
}

/** sha256(method + path + тело): тот же ключ с другим телом → Mismatch → 422. */
private fun requestHash(method: String, path: String, body: Any): String =
    MessageDigest.getInstance("SHA-256").digest("$method $path ${body.hashCode()}".toByteArray()).joinToString("") { "%02x".format(it) }
