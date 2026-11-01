package dev.atrium.ktor.di

import io.opentelemetry.api.OpenTelemetry
import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.context.propagation.ContextPropagators
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor
import io.opentelemetry.sdk.trace.samplers.Sampler

/** OTel SDK для app-ktor: OTLP/HTTP в Collector, parent-based ratio sampling; health и /metrics не трассируются. */
fun buildOpenTelemetry(endpoint: String, samplingRatio: Double, env: String): OpenTelemetry {
    val resource = Resource.getDefault().merge(
        Resource.create(
            Attributes.of(
                AttributeKey.stringKey("service.name"), "atrium-ktor",
                AttributeKey.stringKey("deployment.environment"), env,
            ),
        ),
    )
    val exporter = OtlpHttpSpanExporter.builder().setEndpoint("$endpoint/v1/traces").build()
    val tracerProvider = SdkTracerProvider.builder()
        .setResource(resource)
        .setSampler(Sampler.parentBased(Sampler.traceIdRatioBased(samplingRatio)))
        .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
        .build()
    return OpenTelemetrySdk.builder()
        .setTracerProvider(tracerProvider)
        .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
        .build()
}
