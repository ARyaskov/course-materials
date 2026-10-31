//! tracing setup shared by every binary. Human-readable output locally, JSON
//! lines in containers, filtering through `RUST_LOG`. With the `otel`
//! feature and `COURSEFLOW_OTLP_ENDPOINT` set, spans are also exported over
//! OTLP/HTTP to a collector (Jaeger, Tempo, the OpenTelemetry Collector).

use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogFormat {
    Pretty,
    Json,
}

impl LogFormat {
    pub fn from_env() -> Self {
        match std::env::var("COURSEFLOW_LOG_FORMAT").as_deref() {
            Ok("json") => LogFormat::Json,
            _ => LogFormat::Pretty,
        }
    }
}

/// Handle returned by [`init`]: keeps the exporter alive and flushes it on
/// shutdown. Dropping it without `shutdown` loses the last batch of spans.
#[derive(Debug, Default)]
pub struct Telemetry {
    #[cfg(feature = "otel")]
    provider: Option<opentelemetry_sdk::trace::SdkTracerProvider>,
}

impl Telemetry {
    /// Flushes buffered spans. Call it last, after the pool is closed:
    /// nothing after this point is traced.
    pub fn shutdown(self) {
        #[cfg(feature = "otel")]
        if let Some(provider) = self.provider
            && let Err(err) = provider.shutdown()
        {
            eprintln!("telemetry shutdown failed: {err}");
        }
    }
}

/// Installs the global subscriber. Safe to call once per process; a second
/// call (tests) is a no-op instead of a panic.
#[must_use = "keep the handle until shutdown so that the exporter is flushed"]
pub fn init(service_name: &'static str, format: LogFormat) -> Telemetry {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,courseflow=debug,sqlx=warn,tower_http=info"));
    let registry = tracing_subscriber::registry().with(filter);

    #[cfg(feature = "otel")]
    let (otel_layer, provider) = match otel::layer(service_name) {
        Ok(Some((layer, provider))) => (Some(layer), Some(provider)),
        Ok(None) => (None, None),
        Err(err) => {
            eprintln!("otlp exporter not started: {err}");
            (None, None)
        }
    };
    #[cfg(feature = "otel")]
    let registry = registry.with(otel_layer);

    let result = match format {
        LogFormat::Json => registry
            .with(fmt::layer().json().with_current_span(true).with_span_list(false).flatten_event(true))
            .try_init(),
        LogFormat::Pretty => registry.with(fmt::layer().compact().with_target(true)).try_init(),
    };
    if result.is_ok() {
        tracing::info!(service = service_name, ?format, "telemetry initialized");
    }
    Telemetry {
        #[cfg(feature = "otel")]
        provider,
    }
}

#[cfg(feature = "otel")]
mod otel {
    use opentelemetry::trace::TracerProvider as _;
    use opentelemetry_otlp::WithExportConfig;
    use opentelemetry_sdk::Resource;
    use opentelemetry_sdk::trace::SdkTracerProvider;
    use tracing_subscriber::registry::LookupSpan;

    type Layer<S> = tracing_opentelemetry::OpenTelemetryLayer<S, opentelemetry_sdk::trace::Tracer>;

    /// `COURSEFLOW_OTLP_ENDPOINT` (e.g. `http://localhost:4318`) selects the
    /// collector; unset means "no export", not an error.
    pub fn layer<S>(service_name: &'static str) -> anyhow::Result<Option<(Layer<S>, SdkTracerProvider)>>
    where
        S: tracing::Subscriber + for<'a> LookupSpan<'a>,
    {
        let Ok(endpoint) = std::env::var("COURSEFLOW_OTLP_ENDPOINT") else { return Ok(None) };
        let exporter = opentelemetry_otlp::SpanExporter::builder()
            .with_http()
            .with_endpoint(format!("{}/v1/traces", endpoint.trim_end_matches('/')))
            .build()?;
        let provider = SdkTracerProvider::builder()
            .with_batch_exporter(exporter)
            .with_resource(Resource::builder().with_service_name(service_name).build())
            .build();
        opentelemetry::global::set_tracer_provider(provider.clone());
        let tracer = provider.tracer(service_name);
        Ok(Some((tracing_opentelemetry::layer().with_tracer(tracer), provider)))
    }
}
