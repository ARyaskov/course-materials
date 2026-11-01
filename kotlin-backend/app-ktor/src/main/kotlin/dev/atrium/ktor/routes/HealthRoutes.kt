package dev.atrium.ktor.routes

import dev.atrium.infrastructure.events.KafkaConsumerLoop
import dev.atrium.ktor.plugins.Readiness
import dev.atrium.ktor.plugins.respondProblem
import io.ktor.http.HttpStatusCode
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import javax.sql.DataSource
import kotlin.time.Duration.Companion.seconds

/** liveness — процесс отвечает; readiness — флаг + БД с таймаутом + consumer; PayGate только в деталях (урок 15.2). */
fun Route.healthRoutes(readiness: Readiness, dataSource: DataSource, consumer: KafkaConsumerLoop?, dbDispatcher: CoroutineDispatcher, details: () -> Map<String, String> = { emptyMap() }) {
    get("/healthz") { call.respondText("ok") }

    get("/readyz") {
        if (!readiness.ready) return@get call.respondProblem(HttpStatusCode.ServiceUnavailable, "not-ready", "starting or stopping")
        val checks = coroutineScope {
            val db = async { withTimeoutOrNull(2.seconds) { withContext(dbDispatcher) { dataSource.connection.use { it.isValid(1) } } } ?: false }
            val kafka = async { consumer?.isRunning ?: true }
            mapOf("db" to db.await(), "kafka" to kafka.await())
        }
        val status = if (checks.values.all { it }) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable
        call.respond(status, checks + details())
    }

    get("/info") {
        call.respond(mapOf("version" to (System.getenv("ATRIUM_VERSION") ?: "dev"), "java" to Runtime.version().toString()))
    }
}
