use std::sync::Arc;

use axum::extract::FromRef;
use courseflow_app::auth::AuthService;
use courseflow_app::billing::{BillingService, WebhookVerifier};
use courseflow_app::cache::{IdempotencyGuard, RateLimiter, RedisHandle};
use courseflow_app::config::Config;
use courseflow_app::courses::CourseService;
use courseflow_app::enrollments::EnrollmentService;
use courseflow_app::lessons::LessonService;
use courseflow_app::notifications::NotificationService;
use courseflow_app::progress::ProgressService;
use courseflow_app::users::UserService;
use sqlx::PgPool;

/// Composition root of the API process. Cheap to clone: every field is an
/// `Arc`, a pool handle or a small `Clone` service.
#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub pool: PgPool,
    pub redis: Option<RedisHandle>,
    pub auth: AuthService,
    pub users: UserService,
    pub courses: CourseService,
    pub lessons: LessonService,
    pub enrollments: EnrollmentService,
    pub progress: ProgressService,
    pub billing: BillingService,
    pub notifications: NotificationService,
    pub rate_limiter: RateLimiter,
    pub idempotency: IdempotencyGuard,
    pub webhook_verifier: WebhookVerifier,
}

impl std::fmt::Debug for AppState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AppState")
    }
}

// Sub-state extraction: handlers that need only one service can take
// `State<AuthService>` and stay decoupled from the whole graph.
impl FromRef<AppState> for AuthService {
    fn from_ref(state: &AppState) -> Self {
        state.auth.clone()
    }
}

impl FromRef<AppState> for CourseService {
    fn from_ref(state: &AppState) -> Self {
        state.courses.clone()
    }
}
