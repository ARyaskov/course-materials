//! SIGTERM (Docker, Kubernetes) and Ctrl-C both flip one `CancellationToken`.
//! Everything long-lived — the HTTP server, the pub/sub subscriber, workers —
//! watches that token.

use tokio_util::sync::CancellationToken;

pub fn install_signal_handler() -> CancellationToken {
    let token = CancellationToken::new();
    let trigger = token.clone();
    tokio::spawn(async move {
        let ctrl_c = async {
            if let Err(err) = tokio::signal::ctrl_c().await {
                tracing::error!(error = %err, "failed to listen for ctrl-c");
            }
        };
        #[cfg(unix)]
        let terminate = async {
            match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
                Ok(mut sig) => {
                    sig.recv().await;
                }
                Err(err) => tracing::error!(error = %err, "failed to listen for SIGTERM"),
            }
        };
        #[cfg(not(unix))]
        let terminate = std::future::pending::<()>();
        tokio::select! {
            _ = ctrl_c => tracing::info!("ctrl-c received"),
            _ = terminate => tracing::info!("SIGTERM received"),
        }
        trigger.cancel();
    });
    token
}
