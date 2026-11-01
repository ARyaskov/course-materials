package dev.atrium.ktor.plugins

import io.ktor.http.HttpHeaders
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.request.path
import io.opentelemetry.api.OpenTelemetry
import io.opentelemetry.api.trace.SpanKind
import io.opentelemetry.instrumentation.ktor.v3_0.KtorServerTelemetry

/** Серверный span на каждый запрос; контекст попадает в корутину вызова, Tracing.span внутри становится дочерним (урок 14.3). */
fun Application.configureTracing(openTelemetry: OpenTelemetry) {
    install(KtorServerTelemetry) {
        setOpenTelemetry(openTelemetry)
        capturedRequestHeaders(HttpHeaders.XRequestId)
        spanKindExtractor { if (path().startsWith("/internal")) SpanKind.INTERNAL else SpanKind.SERVER }
    }
}
