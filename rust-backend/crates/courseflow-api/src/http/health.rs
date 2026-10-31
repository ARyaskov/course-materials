//! `/health/live` answers "the process is up"; `/health/ready` answers "it
//! can serve traffic" and probes PostgreSQL and Redis with short timeouts.

use std::time::Duration;

use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use serde::Serialize;
use utoipa::ToSchema;

use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema)]
pub struct HealthStatus {
    pub status: &'static str,
    pub checks: Vec<Check>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Check {
    pub name: &'static str,
    pub ok: bool,
}

#[utoipa::path(get, path = "/health/live", tag = "health", responses((status = 200, body = HealthStatus)))]
pub async fn live() -> Json<HealthStatus> {
    Json(HealthStatus { status: "ok", checks: vec![] })
}

#[utoipa::path(get, path = "/health/ready", tag = "health", responses((status = 200, body = HealthStatus), (status = 503, body = HealthStatus)))]
pub async fn ready(State(state): State<AppState>) -> impl IntoResponse {
    let probe = Duration::from_secs(2);
    let db_ok =
        tokio::time::timeout(probe, courseflow_app::db::ping(&state.pool)).await.map(|r| r.is_ok()).unwrap_or(false);
    let redis_ok = match &state.redis {
        Some(redis) => tokio::time::timeout(probe, redis.ping()).await.map(|r| r.is_ok()).unwrap_or(false),
        None => true,
    };
    let checks = vec![Check { name: "postgres", ok: db_ok }, Check { name: "redis", ok: redis_ok }];
    // Redis is optional for serving reads; PostgreSQL is not.
    let ready = db_ok;
    let status = if ready { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE };
    (status, Json(HealthStatus { status: if ready { "ok" } else { "degraded" }, checks }))
}
