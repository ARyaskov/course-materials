use std::sync::Arc;

use courseflow_core::ids::UserId;
use courseflow_core::policy::{self, Actor};
use courseflow_core::ports::Clock;
use courseflow_core::users::{Role, User};
use sqlx::PgPool;

use crate::errors::{AppError, AppResult};
use crate::users::repo;

/// Profile and administration use cases. Registration and login live in
/// `auth::AuthService` because they need the hasher and token machinery.
#[derive(Clone)]
pub struct UserService {
    pool: PgPool,
    clock: Arc<dyn Clock>,
}

impl std::fmt::Debug for UserService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("UserService")
    }
}

impl UserService {
    pub fn new(pool: PgPool, clock: Arc<dyn Clock>) -> Self {
        Self { pool, clock }
    }

    #[tracing::instrument(skip(self))]
    pub async fn get(&self, id: UserId) -> AppResult<User> {
        repo::find_by_id(&self.pool, id).await?.ok_or(AppError::not_found("user"))
    }

    /// Admin-only: change a user's role (e.g. promote a student to author).
    #[tracing::instrument(skip(self))]
    pub async fn change_role(&self, actor: &Actor, target: UserId, role: Role) -> AppResult<User> {
        policy::require_admin(actor)?;
        let mut user = self.get(target).await?;
        user.promote(role, self.clock.now());
        repo::update(&self.pool, &user).await?;
        Ok(user)
    }
}
