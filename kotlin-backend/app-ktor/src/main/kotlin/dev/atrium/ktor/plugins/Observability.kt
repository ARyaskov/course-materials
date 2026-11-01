package dev.atrium.ktor.plugins

import io.ktor.http.HttpHeaders
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.metrics.micrometer.MicrometerMetrics
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.callid.CallId
import io.ktor.server.plugins.callid.callIdMdc
import io.ktor.server.plugins.defaultheaders.DefaultHeaders
import io.ktor.server.request.path
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import org.slf4j.event.Level
import kotlin.uuid.Uuid

val prometheusRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)

fun Application.configureObservability() {
    install(CallId) {
        header(HttpHeaders.XRequestId)
        generate { Uuid.random().toString() }
        verify { it.length in 8..128 }
    }
    install(CallLogging) {
        level = Level.INFO
        callIdMdc("requestId")
        filter { call -> !call.request.path().startsWith("/healthz") }
    }
    install(DefaultHeaders) {
        header("X-Content-Type-Options", "nosniff")
    }
    install(MicrometerMetrics) {
        registry = prometheusRegistry
    }
}
