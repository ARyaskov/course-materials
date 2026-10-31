//! Wiring: configuration → adapters → services → router.

use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::routing::get;
use courseflow_app::auth::{Argon2Hasher, AuthService, JwtSigner};
use courseflow_app::billing::{BillingService, HttpBillingClient, WebhookVerifier};
use courseflow_app::cache::{CourseCache, IdempotencyGuard, RateLimiter};
use courseflow_app::config::Config;
use courseflow_app::courses::CourseService;
use courseflow_app::enrollments::EnrollmentService;
use courseflow_app::lessons::LessonService;
use courseflow_app::notifications::{NotificationBus, NotificationService};
use courseflow_app::progress::ProgressService;
use courseflow_app::users::UserService;
use courseflow_core::ports::{BillingClient, Clock, PasswordHasher, SystemClock};
use sqlx::PgPool;

use crate::features;
use crate::http::{health, metrics, middleware, openapi};
use crate::state::AppState;

/// Everything that can be swapped in tests goes through this struct; the
/// production `main` fills it with real adapters.
pub struct Dependencies {
    pub pool: PgPool,
    pub redis: Option<courseflow_app::cache::RedisHandle>,
    pub billing: Arc<dyn BillingClient>,
    pub hasher: Arc<dyn PasswordHasher>,
    pub clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for Dependencies {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Dependencies")
    }
}

impl Dependencies {
    /// Production adapters: Argon2, real billing HTTP client, system clock.
    pub async fn from_config(config: &Config) -> anyhow::Result<Self> {
        let pool = courseflow_app::db::connect(&config.database)?;
        let redis = match courseflow_app::cache::connect(&config.redis).await {
            Ok(handle) => Some(handle),
            Err(err) => {
                tracing::warn!(error = %err, "redis unavailable at startup; running without cache, rate limits and idempotency");
                None
            }
        };
        let callback_url = format!("{}/api/v1/webhooks/billing", config.public_base_url.trim_end_matches('/'));
        Ok(Self {
            pool,
            redis,
            billing: Arc::new(HttpBillingClient::new(&config.billing, callback_url)?),
            hasher: Arc::new(Argon2Hasher::from_config(&config.auth)?),
            clock: Arc::new(SystemClock),
        })
    }
}

pub fn build_state(config: Config, deps: Dependencies) -> AppState {
    let config = Arc::new(config);
    let pool = deps.pool;
    let clock = deps.clock;
    let jwt = JwtSigner::new(&config.auth.jwt_secret, config.auth.access_ttl);
    let bus = NotificationBus::new(deps.redis.clone());
    AppState {
        auth: AuthService::new(pool.clone(), deps.hasher, jwt, clock.clone(), &config.auth),
        users: UserService::new(pool.clone(), clock.clone()),
        courses: CourseService::new(
            pool.clone(),
            clock.clone(),
            CourseCache::new(deps.redis.clone(), Duration::from_secs(300)),
        ),
        lessons: LessonService::new(pool.clone(), clock.clone()),
        enrollments: EnrollmentService::new(pool.clone(), clock.clone()),
        progress: ProgressService::new(pool.clone(), clock.clone()),
        billing: BillingService::new(pool.clone(), deps.billing, clock.clone()),
        notifications: NotificationService::new(pool.clone(), bus, clock),
        rate_limiter: RateLimiter::new(deps.redis.clone(), true),
        idempotency: IdempotencyGuard::new(deps.redis.clone(), Duration::from_secs(24 * 3600)),
        webhook_verifier: WebhookVerifier::new(config.billing.webhook_secret.clone(), 300),
        redis: deps.redis,
        pool,
        config,
    }
}

pub fn build_router(state: AppState) -> Router {
    let api = Router::new()
        .merge(features::auth::router())
        .merge(features::users::router())
        .merge(features::courses::router())
        .merge(features::lessons::router())
        .merge(features::enrollments::router())
        .merge(features::progress::router())
        .merge(features::billing::router())
        .merge(features::notifications::router());

    // `/admin/*`: one role guard on the whole group (defence in depth — the
    // use cases check `require_admin` again). `route_layer` runs only for
    // matched routes, so an unknown `/admin/...` path is still a plain 404.
    let admin = Router::new()
        .merge(features::users::admin_router())
        .merge(features::enrollments::admin_router())
        .route_layer(axum::middleware::from_fn_with_state(state.clone(), middleware::require_admin));

    let router = Router::new()
        .route("/health/live", get(health::live))
        .route("/health/ready", get(health::ready))
        .route("/metrics", get(metrics::render))
        .route("/api/docs/openapi.json", get(openapi::openapi_json))
        .nest("/api/v1", api)
        .nest("/api/v1/admin", admin)
        .fallback(|| async { crate::http::ApiError::NotFound("route") });

    middleware::apply(router, &state.config.http).with_state(state)
}
