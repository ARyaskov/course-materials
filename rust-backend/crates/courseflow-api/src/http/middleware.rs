//! Cross-cutting layers: request id, tracing, timeouts, body limit, CORS,
//! HTTP metrics. Business logic never lives here.

use std::time::{Duration, Instant};

use axum::Router;
use axum::body::Body;
use axum::extract::{MatchedPath, Request};
use axum::http::{HeaderName, HeaderValue, Method, header};
use axum::middleware::Next;
use axum::response::Response;
use tower::ServiceBuilder;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::set_header::SetResponseHeaderLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing::Level;

use crate::http::error::ApiError;
use crate::http::extractors::CurrentUser;
use courseflow_core::users::Role;

use crate::state::AppState;

const REQUEST_ID: HeaderName = HeaderName::from_static("x-request-id");

pub fn apply(router: Router<AppState>, config: &courseflow_app::config::HttpConfig) -> Router<AppState> {
    let cors = if config.cors_allowed_origins.is_empty() {
        CorsLayer::new()
    } else {
        let origins: Vec<HeaderValue> = config.cors_allowed_origins.iter().filter_map(|o| o.parse().ok()).collect();
        CorsLayer::new()
            .allow_origin(AllowOrigin::list(origins))
            .allow_methods([Method::GET, Method::POST, Method::PUT, Method::PATCH, Method::DELETE])
            .allow_headers([
                header::AUTHORIZATION,
                header::CONTENT_TYPE,
                REQUEST_ID,
                HeaderName::from_static("idempotency-key"),
            ])
            .max_age(Duration::from_secs(600))
    };

    let trace = TraceLayer::new_for_http()
        .make_span_with(|request: &Request<Body>| {
            let request_id = request.headers().get(REQUEST_ID).and_then(|v| v.to_str().ok()).unwrap_or("-");
            let route = request.extensions().get::<MatchedPath>().map(MatchedPath::as_str).unwrap_or("unmatched");
            tracing::info_span!(
                "http.request",
                method = %request.method(),
                route,
                request_id,
                user_id = tracing::field::Empty,
                status = tracing::field::Empty,
            )
        })
        .on_response(DefaultOnResponse::new().level(Level::INFO).latency_unit(tower_http::LatencyUnit::Millis));

    // Order matters: the outermost layer runs first on the way in and last on
    // the way out. Request id must exist before tracing reads it; the timeout
    // must wrap everything that can be slow.
    router.layer(axum::middleware::from_fn(problem_request_id)).layer(axum::middleware::from_fn(http_metrics)).layer(
        ServiceBuilder::new()
            .layer(SetRequestIdLayer::new(REQUEST_ID.clone(), MakeRequestUuid))
            .layer(PropagateRequestIdLayer::new(REQUEST_ID.clone()))
            .layer(trace)
            .layer(TimeoutLayer::with_status_code(axum::http::StatusCode::SERVICE_UNAVAILABLE, config.request_timeout))
            .layer(RequestBodyLimitLayer::new(config.body_limit_bytes))
            .layer(SetResponseHeaderLayer::if_not_present(
                header::X_CONTENT_TYPE_OPTIONS,
                HeaderValue::from_static("nosniff"),
            ))
            .layer(SetResponseHeaderLayer::if_not_present(header::CACHE_CONTROL, HeaderValue::from_static("no-store")))
            .layer(cors),
    )
}

/// RED metrics per route: request count and latency histogram.
async fn http_metrics(request: Request, next: Next) -> Response {
    let started = Instant::now();
    let method = request.method().to_string();
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_owned())
        .unwrap_or_else(|| "unmatched".to_owned());
    let response = next.run(request).await;
    let status = response.status().as_u16().to_string();
    let labels = [("method", method), ("route", route), ("status", status)];
    metrics::counter!("courseflow_http_requests_total", &labels).increment(1);
    metrics::histogram!("courseflow_http_request_duration_seconds", &labels).record(started.elapsed().as_secs_f64());
    response
}

/// Problem responses are built before the request id header is propagated;
/// this rewrites `application/problem+json` bodies to include it.
async fn problem_request_id(request: Request, next: Next) -> Response {
    let request_id = request.headers().get(REQUEST_ID).and_then(|v| v.to_str().ok()).map(str::to_owned);
    let response = next.run(request).await;
    let is_problem = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|ct| ct.starts_with("application/problem+json"));
    let Some(request_id) = request_id.filter(|_| is_problem) else { return response };
    let (parts, body) = response.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, 64 * 1024).await else {
        return Response::from_parts(parts, Body::empty());
    };
    let Ok(mut json) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
        return Response::from_parts(parts, Body::from(bytes));
    };
    if let Some(obj) = json.as_object_mut() {
        obj.insert("request_id".into(), serde_json::Value::String(request_id));
    }
    let mut parts = parts;
    parts.headers.remove(header::CONTENT_LENGTH);
    Response::from_parts(parts, Body::from(json.to_string()))
}

/// Route-group guard for `/admin/*`: rejects non-admins before the handler
/// runs. Use cases still call `policy::require_admin` themselves — this layer
/// is an early, uniform 403, not the source of truth.
pub async fn require_admin(user: CurrentUser, request: Request, next: Next) -> Result<Response, ApiError> {
    user.require_role(Role::Admin)?;
    Ok(next.run(request).await)
}
