use std::sync::Arc;

use axum::Router;
use axum::routing::get;
use courseflow_app::config::Config;
use courseflow_app::notifications::{NotificationBus, NotificationService};
use courseflow_app::telemetry::{self, LogFormat};
use courseflow_core::ports::SystemClock;
use courseflow_worker::handlers::Handlers;
use courseflow_worker::periodic;
use courseflow_worker::relay::Relay;
use tokio_util::sync::CancellationToken;
use tokio_util::task::TaskTracker;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    let telemetry = telemetry::init("courseflow-worker", LogFormat::from_env());
    let config = Config::from_env()?;

    let pool = courseflow_app::db::connect(&config.database)?;
    let redis = match courseflow_app::cache::connect(&config.redis).await {
        Ok(handle) => Some(handle),
        Err(err) => {
            tracing::warn!(error = %err, "redis unavailable; notifications will not reach live sockets");
            None
        }
    };
    let bus = NotificationBus::new(redis);
    let notifications = Arc::new(NotificationService::new(pool.clone(), bus, Arc::new(SystemClock)));
    let handlers = Handlers { pool: pool.clone(), notifications };
    let relay = Relay::new(pool.clone(), handlers, &config.worker);

    let cancel = CancellationToken::new();
    install_signals(cancel.clone());
    let tracker = TaskTracker::new();

    tracker.spawn(relay.run(config.worker.outbox_poll_interval, cancel.clone()));
    tracker.spawn(periodic::run_cleanup(pool.clone(), config.worker.cleanup_interval, cancel.clone()));

    // Tiny HTTP surface for liveness and Prometheus, on a separate port.
    let metrics_handle = metrics_exporter_prometheus::PrometheusBuilder::new().install_recorder().ok();
    let health = Router::new().route("/health/live", get(|| async { "ok" })).route(
        "/metrics",
        get(move || {
            let handle = metrics_handle.clone();
            async move { handle.map(|h| h.render()).unwrap_or_default() }
        }),
    );
    let health_addr: std::net::SocketAddr =
        std::env::var("COURSEFLOW_WORKER_HTTP_ADDR").unwrap_or_else(|_| "127.0.0.1:8081".into()).parse()?;
    let listener = tokio::net::TcpListener::bind(health_addr).await?;
    tracing::info!(%health_addr, "courseflow-worker started");
    let server_cancel = cancel.clone();
    tracker.spawn(async move {
        let _ =
            axum::serve(listener, health).with_graceful_shutdown(async move { server_cancel.cancelled().await }).await;
    });

    tracker.close();
    cancel.cancelled().await;
    tracing::info!("shutdown requested, waiting for in-flight work");
    if tokio::time::timeout(config.http.shutdown_timeout, tracker.wait()).await.is_err() {
        tracing::warn!("shutdown timeout elapsed");
    }
    pool.close().await;
    tracing::info!("worker exited");
    telemetry.shutdown();
    Ok(())
}

fn install_signals(cancel: CancellationToken) {
    tokio::spawn(async move {
        let ctrl_c = tokio::signal::ctrl_c();
        #[cfg(unix)]
        let mut term = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(s) => s,
            Err(err) => {
                tracing::error!(error = %err, "cannot install SIGTERM handler");
                return;
            }
        };
        #[cfg(unix)]
        tokio::select! { _ = ctrl_c => {}, _ = term.recv() => {} }
        #[cfg(not(unix))]
        let _ = ctrl_c.await;
        tracing::info!("termination signal received");
        cancel.cancel();
    });
}
