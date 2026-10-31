//! PostgreSQL access: one pool per process, migrations embedded in the binary.

use std::time::Duration;

use secrecy::ExposeSecret;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{AssertSqlSafe, ConnectOptions, PgPool};

use crate::config::DatabaseConfig;

pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../../migrations");

/// Builds the pool. Connecting lazily is deliberate: the API must start even
/// if PostgreSQL is briefly down, and readiness reports the real state.
pub fn connect(config: &DatabaseConfig) -> Result<PgPool, sqlx::Error> {
    let options: PgConnectOptions = config
        .url
        .expose_secret()
        .parse::<PgConnectOptions>()?
        .application_name("courseflow")
        .log_statements(tracing::log::LevelFilter::Debug)
        .log_slow_statements(tracing::log::LevelFilter::Warn, Duration::from_millis(500));

    let statement_timeout_ms = config.statement_timeout.as_millis();
    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .min_connections(config.min_connections)
        .acquire_timeout(config.acquire_timeout)
        .idle_timeout(Duration::from_secs(300))
        .max_lifetime(Duration::from_secs(1800))
        .after_connect(move |conn, _meta| {
            Box::pin(async move {
                // A hung query must never hold a pooled connection forever.
                // SQLx 0.9 refuses non-literal SQL unless we vouch for it: the only
                // dynamic part here is an integer we control, never user input.
                sqlx::query(AssertSqlSafe(format!("SET statement_timeout = {statement_timeout_ms}")))
                    .execute(conn)
                    .await?;
                Ok(())
            })
        })
        .connect_lazy_with(options);
    Ok(pool)
}

pub async fn migrate(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    MIGRATOR.run(pool).await
}

/// Cheap readiness probe used by `/health/ready`.
pub async fn ping(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query_scalar::<_, i32>("SELECT 1").fetch_one(pool).await.map(|_| ())
}
