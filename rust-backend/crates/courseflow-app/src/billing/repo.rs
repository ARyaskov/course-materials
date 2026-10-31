use chrono::{DateTime, Utc};
use courseflow_core::billing::{BillingEvent, Purchase, PurchaseStatus};
use courseflow_core::ids::{CourseId, PurchaseId, UserId};
use courseflow_core::money::{Currency, Money};
use rust_decimal::Decimal;
use sqlx::PgExecutor;
use sqlx::types::Json;
use uuid::Uuid;

use crate::errors::{AppError, AppResult};

#[derive(Debug, sqlx::FromRow)]
struct PurchaseRow {
    id: Uuid,
    user_id: Uuid,
    course_id: Uuid,
    amount: Decimal,
    currency: String,
    status: String,
    provider_payment_id: Option<String>,
    idempotency_key: String,
    failure_reason: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl TryFrom<PurchaseRow> for Purchase {
    type Error = AppError;

    fn try_from(r: PurchaseRow) -> Result<Self, Self::Error> {
        Ok(Purchase {
            id: PurchaseId(r.id),
            user_id: UserId(r.user_id),
            course_id: CourseId(r.course_id),
            amount: Money::new(r.amount, r.currency.parse::<Currency>()?)?,
            status: r.status.parse::<PurchaseStatus>()?,
            provider_payment_id: r.provider_payment_id,
            idempotency_key: r.idempotency_key,
            failure_reason: r.failure_reason,
            created_at: r.created_at,
            updated_at: r.updated_at,
        })
    }
}

macro_rules! select_purchase {
    ($where:literal, $($arg:expr),*) => {
        sqlx::query_as!(
            PurchaseRow,
            "SELECT id, user_id, course_id, amount, currency, status, provider_payment_id, idempotency_key, failure_reason, created_at, updated_at FROM purchases WHERE " + $where,
            $($arg),*
        )
    };
}

pub async fn insert(executor: impl PgExecutor<'_>, p: &Purchase) -> AppResult<()> {
    sqlx::query!(
        r#"INSERT INTO purchases (id, user_id, course_id, amount, currency, status, provider_payment_id, idempotency_key, failure_reason, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)"#,
        p.id.0,
        p.user_id.0,
        p.course_id.0,
        p.amount.amount(),
        p.amount.currency().as_str(),
        p.status.as_str(),
        p.provider_payment_id,
        p.idempotency_key,
        p.failure_reason,
        p.created_at,
        p.updated_at
    )
    .execute(executor)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.is_unique_violation() => AppError::conflict("duplicate purchase"),
        _ => AppError::from(e),
    })?;
    Ok(())
}

pub async fn update(executor: impl PgExecutor<'_>, p: &Purchase) -> AppResult<()> {
    sqlx::query!(
        r#"UPDATE purchases SET status = $2, provider_payment_id = $3, failure_reason = $4, updated_at = $5 WHERE id = $1"#,
        p.id.0,
        p.status.as_str(),
        p.provider_payment_id,
        p.failure_reason,
        p.updated_at
    )
    .execute(executor)
    .await?;
    Ok(())
}

pub async fn find_by_id(executor: impl PgExecutor<'_>, id: PurchaseId) -> AppResult<Option<Purchase>> {
    let row = select_purchase!("id = $1", id.0).fetch_optional(executor).await?;
    row.map(Purchase::try_from).transpose()
}

pub async fn find_by_idempotency_key(
    executor: impl PgExecutor<'_>,
    user_id: UserId,
    key: &str,
) -> AppResult<Option<Purchase>> {
    let row =
        select_purchase!("user_id = $1 AND idempotency_key = $2", user_id.0, key).fetch_optional(executor).await?;
    row.map(Purchase::try_from).transpose()
}

/// Locks the purchase row for the duration of the webhook transaction so two
/// concurrent deliveries serialize instead of racing.
pub async fn find_by_provider_id_for_update(
    executor: impl PgExecutor<'_>,
    provider_payment_id: &str,
) -> AppResult<Option<Purchase>> {
    let row =
        select_purchase!("provider_payment_id = $1 FOR UPDATE", provider_payment_id).fetch_optional(executor).await?;
    row.map(Purchase::try_from).transpose()
}

pub async fn list_for_user(executor: impl PgExecutor<'_>, user_id: UserId) -> AppResult<Vec<Purchase>> {
    let rows = select_purchase!("user_id = $1 ORDER BY created_at DESC", user_id.0).fetch_all(executor).await?;
    rows.into_iter().map(Purchase::try_from).collect()
}

/// Records a webhook delivery. Returns `false` if this provider event id was
/// already seen — the caller then acknowledges without acting.
pub async fn record_event(
    executor: impl PgExecutor<'_>,
    provider_event_id: &str,
    event: &BillingEvent,
) -> AppResult<bool> {
    let event_type = event.kind();
    let r = sqlx::query!(
        r#"INSERT INTO billing_events (provider_event_id, event_type, payload) VALUES ($1, $2, $3)
           ON CONFLICT (provider_event_id) DO NOTHING"#,
        provider_event_id,
        event_type,
        Json(event) as _
    )
    .execute(executor)
    .await?;
    Ok(r.rows_affected() == 1)
}
