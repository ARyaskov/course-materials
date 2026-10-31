//! Prometheus exposition on `/metrics`. The recorder is process-global and
//! installed once by `main`; tests simply skip installation.

use axum::response::IntoResponse;
use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};
use std::sync::OnceLock;

static HANDLE: OnceLock<PrometheusHandle> = OnceLock::new();

pub fn install() -> Result<(), metrics_exporter_prometheus::BuildError> {
    if HANDLE.get().is_some() {
        return Ok(());
    }
    let handle = PrometheusBuilder::new()
        .set_buckets_for_metric(
            metrics_exporter_prometheus::Matcher::Suffix("_seconds".into()),
            &[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
        )?
        .install_recorder()?;
    let _ = HANDLE.set(handle);
    Ok(())
}

pub async fn render() -> impl IntoResponse {
    match HANDLE.get() {
        Some(handle) => ([("content-type", "text/plain; version=0.0.4")], handle.render()).into_response(),
        None => (axum::http::StatusCode::NOT_FOUND, "metrics recorder not installed").into_response(),
    }
}
