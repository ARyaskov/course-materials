package dev.atrium.ktor.plugins

import dev.atrium.application.CancelBooking
import dev.atrium.application.ConfirmBooking
import dev.atrium.application.CreateBooking
import dev.atrium.application.ListMemberBookings
import dev.atrium.application.ports.RoomRepository
import dev.atrium.ktor.routes.bookingRoutes
import dev.atrium.ktor.routes.roomRoutes
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import dev.atrium.ktor.routes.metricsRoutes
import dev.atrium.ktor.routes.healthRoutes
import io.ktor.server.plugins.di.dependencies
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.routing

fun Application.configureRouting() {
    val rooms: RoomRepository by dependencies
    val createBooking: CreateBooking by dependencies
    val confirmBooking: ConfirmBooking by dependencies
    val cancelBooking: CancelBooking by dependencies
    val listBookings: ListMemberBookings by dependencies

    routing {
        roomRoutes(rooms)
        bookingRoutes(createBooking, confirmBooking, cancelBooking, listBookings)
        val readiness: Readiness by dependencies
        val dataSource: javax.sql.DataSource by dependencies
        val dbDispatcher: kotlinx.coroutines.CoroutineDispatcher by dependencies.named("db")
        val paygate: dev.atrium.infrastructure.resilience.ResilientPaymentGateway? = runCatching { val p: dev.atrium.infrastructure.resilience.ResilientPaymentGateway by dependencies; p }.getOrNull()
        healthRoutes(readiness, dataSource, runCatching { val c: dev.atrium.infrastructure.events.KafkaConsumerLoop by dependencies; c }.getOrNull(), dbDispatcher) {
            mapOf("paygate" to (paygate?.breakerState?.name ?: "n/a"))
        }
        metricsRoutes(prometheusRegistry)
    }
}
