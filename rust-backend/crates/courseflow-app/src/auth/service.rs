use std::sync::Arc;
use std::time::Duration;

use chrono::{DateTime, Utc};
use courseflow_core::ids::UserId;
use courseflow_core::notifications::NotificationEvent;
use courseflow_core::ports::{Clock, PasswordHasher};
use courseflow_core::users::{Email, Role, User, validate_password};
use secrecy::{ExposeSecret, SecretString};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::jwt::{JwtError, JwtSigner};
use crate::auth::refresh::{self, ActionPurpose};
use crate::auth::tokens;
use crate::config::AuthConfig;
use crate::errors::{AppError, AppResult};
use crate::outbox;
use crate::users::repo as users;

#[derive(Debug, Clone)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: SecretString,
    pub access_expires_in: Duration,
}

/// Registration, login, refresh rotation, logout, password reset, e-mail
/// verification. Everything that touches credentials goes through here.
#[derive(Clone)]
pub struct AuthService {
    pool: PgPool,
    hasher: Arc<dyn PasswordHasher>,
    jwt: JwtSigner,
    clock: Arc<dyn Clock>,
    refresh_ttl: Duration,
    action_token_ttl: Duration,
}

impl std::fmt::Debug for AuthService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AuthService")
    }
}

impl AuthService {
    pub fn new(
        pool: PgPool,
        hasher: Arc<dyn PasswordHasher>,
        jwt: JwtSigner,
        clock: Arc<dyn Clock>,
        config: &AuthConfig,
    ) -> Self {
        Self { pool, hasher, jwt, clock, refresh_ttl: config.refresh_ttl, action_token_ttl: config.action_token_ttl }
    }

    pub fn jwt(&self) -> &JwtSigner {
        &self.jwt
    }

    #[tracing::instrument(skip_all, fields(email = %email))]
    pub async fn register(&self, email: Email, display_name: &str, password: &SecretString) -> AppResult<User> {
        validate_password(password.expose_secret())?;
        let now = self.clock.now();
        let hash = self.hasher.hash(password.expose_secret()).await?;
        let user = User::register(email, display_name, hash, now)?;

        // The welcome notification and the verification e-mail are side effects
        // of the same business fact: they are written in the same transaction.
        let mut tx = self.pool.begin().await?;
        users::insert(&mut *tx, &user).await?;
        let verify_secret = tokens::generate_secret();
        refresh::insert_action_token(
            &mut *tx,
            user.id,
            ActionPurpose::EmailVerification,
            &tokens::digest(&verify_secret),
            now + self.action_token_ttl,
        )
        .await?;
        outbox::enqueue(
            &mut *tx,
            &outbox::OutboxPayload::Notify {
                user_id: user.id,
                event: NotificationEvent::Welcome { display_name: user.display_name.clone() },
            },
            now,
        )
        .await?;
        outbox::enqueue(
            &mut *tx,
            &outbox::OutboxPayload::Notify {
                user_id: user.id,
                event: NotificationEvent::EmailVerification { token_hint: hint(&verify_secret) },
            },
            now,
        )
        .await?;
        tx.commit().await?;

        tracing::info!(user_id = %user.id, "user registered");
        Ok(user)
    }

    /// Wrong e-mail and wrong password produce the same error and take
    /// roughly the same time: a missing user still costs one hash check.
    #[tracing::instrument(skip_all, fields(email = %email))]
    pub async fn login(&self, email: &Email, password: &SecretString) -> AppResult<(User, TokenPair)> {
        let now = self.clock.now();
        let user = users::find_by_email(&self.pool, email).await?;
        let Some(user) = user else {
            let _ = self.hasher.verify(password.expose_secret(), &dummy_hash()).await;
            return Err(AppError::Unauthorized("invalid credentials"));
        };
        if !self.hasher.verify(password.expose_secret(), &user.password_hash).await? {
            tracing::warn!(user_id = %user.id, "failed login attempt");
            return Err(AppError::Unauthorized("invalid credentials"));
        }
        // The only moment the plaintext is available: upgrade hashes made
        // with weaker parameters.
        let mut user = user;
        if self.hasher.needs_rehash(&user.password_hash) {
            user.password_hash = self.hasher.hash(password.expose_secret()).await?;
            user.updated_at = now;
            users::update(&self.pool, &user).await?;
            tracing::info!(user_id = %user.id, "password hash upgraded");
        }
        let pair = self.issue_pair(&user, Uuid::now_v7(), now).await?;
        tracing::info!(user_id = %user.id, "login ok");
        Ok((user, pair))
    }

    #[tracing::instrument(skip_all)]
    pub async fn refresh(&self, refresh_token: &SecretString) -> AppResult<(User, TokenPair)> {
        let now = self.clock.now();
        let hash = tokens::digest(refresh_token.expose_secret());
        let Some(record) = refresh::find_by_hash(&self.pool, &hash).await? else {
            return Err(AppError::Unauthorized("invalid refresh token"));
        };
        if record.replaced_by.is_some() || record.revoked_at.is_some() {
            // Reuse of a rotated token: assume theft, kill the whole family.
            let revoked = refresh::revoke_family(&self.pool, record.family_id, now).await?;
            tracing::warn!(user_id = %record.user_id, family = %record.family_id, revoked, "refresh token reuse detected");
            return Err(AppError::Unauthorized("refresh token reuse detected"));
        }
        if !record.is_active(now) {
            return Err(AppError::Unauthorized("refresh token expired"));
        }
        let user = users::find_by_id(&self.pool, record.user_id)
            .await?
            .ok_or(AppError::Unauthorized("user no longer exists"))?;

        let mut tx = self.pool.begin().await?;
        let new_id = Uuid::now_v7();
        let pair = self.issue_pair_tx(&mut tx, &user, record.family_id, new_id, now).await?;
        refresh::mark_replaced(&mut *tx, record.id, new_id).await?;
        tx.commit().await?;
        Ok((user, pair))
    }

    #[tracing::instrument(skip_all)]
    pub async fn logout(&self, refresh_token: &SecretString) -> AppResult<()> {
        let hash = tokens::digest(refresh_token.expose_secret());
        if let Some(record) = refresh::find_by_hash(&self.pool, &hash).await? {
            refresh::revoke_family(&self.pool, record.family_id, self.clock.now()).await?;
        }
        // Unknown token: nothing to do, and nothing to reveal.
        Ok(())
    }

    pub async fn logout_everywhere(&self, user_id: UserId) -> AppResult<u64> {
        refresh::revoke_all_for_user(&self.pool, user_id, self.clock.now()).await
    }

    /// Always succeeds from the caller's point of view: the response must not
    /// reveal whether the e-mail is registered.
    #[tracing::instrument(skip_all)]
    pub async fn request_password_reset(&self, email: &Email) -> AppResult<()> {
        let Some(user) = users::find_by_email(&self.pool, email).await? else {
            return Ok(());
        };
        let now = self.clock.now();
        let secret = tokens::generate_secret();
        let mut tx = self.pool.begin().await?;
        refresh::insert_action_token(
            &mut *tx,
            user.id,
            ActionPurpose::PasswordReset,
            &tokens::digest(&secret),
            now + self.action_token_ttl,
        )
        .await?;
        outbox::enqueue(
            &mut *tx,
            &outbox::OutboxPayload::Notify {
                user_id: user.id,
                event: NotificationEvent::PasswordReset { token_hint: hint(&secret) },
            },
            now,
        )
        .await?;
        tx.commit().await?;
        // Delivery of the full token belongs in a private e-mail channel.
        // Logs record only the event and user id, never the token itself.
        tracing::info!(user_id = %user.id, "password reset requested");
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    pub async fn reset_password(&self, token: &SecretString, new_password: &SecretString) -> AppResult<()> {
        validate_password(new_password.expose_secret())?;
        let now = self.clock.now();
        let mut tx = self.pool.begin().await?;
        let Some(user_id) = refresh::consume_action_token(
            &mut *tx,
            ActionPurpose::PasswordReset,
            &tokens::digest(token.expose_secret()),
            now,
        )
        .await?
        else {
            return Err(AppError::Unauthorized("invalid or expired reset token"));
        };
        let mut user = users::find_by_id(&mut *tx, user_id).await?.ok_or(AppError::not_found("user"))?;
        user.password_hash = self.hasher.hash(new_password.expose_secret()).await?;
        user.updated_at = now;
        users::update(&mut *tx, &user).await?;
        // A password change invalidates every session.
        refresh::revoke_all_for_user(&mut *tx, user_id, now).await?;
        tx.commit().await?;
        tracing::info!(user_id = %user_id, "password reset completed");
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    pub async fn verify_email(&self, token: &SecretString) -> AppResult<User> {
        let now = self.clock.now();
        let mut tx = self.pool.begin().await?;
        let Some(user_id) = refresh::consume_action_token(
            &mut *tx,
            ActionPurpose::EmailVerification,
            &tokens::digest(token.expose_secret()),
            now,
        )
        .await?
        else {
            return Err(AppError::Unauthorized("invalid or expired verification token"));
        };
        let mut user = users::find_by_id(&mut *tx, user_id).await?.ok_or(AppError::not_found("user"))?;
        user.verify_email(now);
        users::update(&mut *tx, &user).await?;
        tx.commit().await?;
        Ok(user)
    }

    /// Validates an access token and returns the principal it carries.
    pub fn authenticate(&self, bearer: &str) -> Result<(UserId, Role), JwtError> {
        let claims = self.jwt.verify(bearer)?;
        Ok((claims.sub, claims.role))
    }

    async fn issue_pair(&self, user: &User, family_id: Uuid, now: DateTime<Utc>) -> AppResult<TokenPair> {
        let mut tx = self.pool.begin().await?;
        let pair = self.issue_pair_tx(&mut tx, user, family_id, Uuid::now_v7(), now).await?;
        tx.commit().await?;
        Ok(pair)
    }

    async fn issue_pair_tx(
        &self,
        tx: &mut sqlx::PgConnection,
        user: &User,
        family_id: Uuid,
        token_id: Uuid,
        now: DateTime<Utc>,
    ) -> AppResult<TokenPair> {
        let access_token =
            self.jwt.issue(user.id, user.role, now).map_err(|e| AppError::Internal(anyhow::Error::new(e)))?;
        let secret = tokens::generate_secret();
        refresh::insert(&mut *tx, token_id, user.id, family_id, &tokens::digest(&secret), now + self.refresh_ttl, now)
            .await?;
        Ok(TokenPair {
            access_token,
            refresh_token: SecretString::from(secret),
            access_expires_in: self.jwt.access_ttl(),
        })
    }
}

fn hint(secret: &str) -> String {
    format!("{}…", &secret[..6])
}

/// A real Argon2id hash of an unrelated password, used to equalize timing
/// when the e-mail is unknown.
fn dummy_hash() -> courseflow_core::users::PasswordHash {
    courseflow_core::users::PasswordHash::from_phc(
        "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$Q2lRXn3hK6rbnV7cQ4yD8uKcJ1xgqk5lJm7cyB4v2u0".to_owned(),
    )
}
