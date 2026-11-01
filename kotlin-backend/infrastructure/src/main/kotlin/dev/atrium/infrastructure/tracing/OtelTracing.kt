package dev.atrium.infrastructure.tracing

import dev.atrium.application.ports.SpanScope
import dev.atrium.application.ports.Tracing
import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.trace.Span
import io.opentelemetry.api.trace.StatusCode
import io.opentelemetry.api.trace.Tracer
import io.opentelemetry.context.Context
import io.opentelemetry.extension.kotlin.asContextElement
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.slf4j.MDCContext
import kotlinx.coroutines.withContext

class OtelTracing(private val tracer: Tracer) : Tracing {
    override suspend fun <T> span(name: String, attributes: Map<String, Any>, block: suspend SpanScope.() -> T): T {
        val span = tracer.spanBuilder(name).setParent(Context.current()).startSpan()
        attributes.forEach { (k, v) -> span.setAttribute(k, v.toString()) }
        // asContextElement — контекст OTel переживает suspension; MDCContext — traceId в каждой записи лога
        return withContext(span.asContextElement() + MDCContext(mapOf("traceId" to span.spanContext.traceId, "spanId" to span.spanContext.spanId))) {
            try {
                block(OtelSpanScope(span))
            } catch (e: CancellationException) {
                span.setStatus(StatusCode.ERROR, "cancelled")
                throw e
            } catch (e: Exception) {
                span.recordException(e)
                span.setStatus(StatusCode.ERROR)
                throw e
            } finally {
                span.end()
            }
        }
    }
}

private class OtelSpanScope(private val span: Span) : SpanScope {
    override fun event(name: String, attributes: Map<String, Any>) {
        span.addEvent(name, attributes.toAttributes())
    }

    override fun attribute(key: String, value: Any) {
        span.setAttribute(key, value.toString())
    }
}

private fun Map<String, Any>.toAttributes(): Attributes = Attributes.builder().also { b ->
    forEach { (k, v) -> b.put(AttributeKey.stringKey(k), v.toString()) }
}.build()
