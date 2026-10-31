use std::net::SocketAddr;

use courseflow_api::app::Dependencies;
use courseflow_app::config::{Config, Environment};
use courseflow_app::telemetry::{self, LogFormat};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // `.env` is a local convenience; containers get real environment variables.
    let _ = dotenvy::dotenv();
    let telemetry = telemetry::init("courseflow-api", LogFormat::from_env());

    let config = Config::from_env()?;
    if config.environment != Environment::Test
        && let Err(err) = courseflow_api::http::metrics::install()
    {
        tracing::warn!(error = %err, "metrics recorder not installed");
    }

    // `courseflow-api migrate` applies migrations and exits: the same image
    // serves as the migration job in Compose/CI.
    if std::env::args().nth(1).as_deref() == Some("migrate") {
        let pool = courseflow_app::db::connect(&config.database)?;
        courseflow_app::db::migrate(&pool).await?;
        tracing::info!("migrations applied");
        return Ok(());
    }

    let deps = Dependencies::from_config(&config).await?;
    let shutdown = courseflow_api::http::shutdown::install_signal_handler();
    let addr = config.http.addr;
    let shutdown_timeout = config.http.shutdown_timeout;
    let redis_config = config.redis.clone();
    let state = courseflow_api::build_state(config, deps);
    let state_pool = state.pool.clone();

    // Redis pub/sub → local broadcast, so this instance delivers events
    // produced by the worker to its WebSocket/SSE clients.
    let subscriber = {
        let bus = state.notifications.bus().clone();
        let token = shutdown.clone();
        tokio::spawn(async move { bus.run_subscriber(&redis_config, token).await })
    };

    let app = courseflow_api::build_router(state);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "courseflow-api listening");

    let server =
        axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown({
            let token = shutdown.clone();
            async move { token.cancelled().await }
        });
    let mut server = tokio::spawn(async move { server.await });

    // Graceful shutdown: the deadline starts *after* the signal, not at
    // startup — wrapping `serve` itself in a timeout would kill a healthy
    // server after `shutdown_timeout` seconds.
    tokio::select! {
        result = &mut server => match result {
            Ok(Ok(())) => tracing::info!("server stopped"),
            Ok(Err(err)) => tracing::error!(error = %err, "server error"),
            Err(err) => tracing::error!(error = %err, "server task panicked"),
        },
        _ = shutdown.cancelled() => {
            tracing::info!(?shutdown_timeout, "shutdown requested, draining in-flight requests");
            match tokio::time::timeout(shutdown_timeout, &mut server).await {
                Ok(_) => tracing::info!("server stopped cleanly"),
                Err(_) => {
                    tracing::warn!("shutdown timeout elapsed, exiting with in-flight requests");
                    server.abort();
                }
            }
        }
    }
    subscriber.abort();
    // Order matters: pool and Redis first (their last spans still get
    // exported), telemetry last (flushes buffered spans, then nothing is
    // traced any more).
    state_pool.close().await;
    tracing::info!("api exited");
    telemetry.shutdown();
    Ok(())
}
