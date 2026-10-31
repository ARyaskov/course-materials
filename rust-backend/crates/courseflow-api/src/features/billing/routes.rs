use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use courseflow_app::AppError;
use std::time::Duration;

use courseflow_app::cache::idempotency::StoredResponse;
use courseflow_app::cache::{IdempotencyOutcome, RateLimitDecision};
use courseflow_core::ids::{CourseId, PurchaseId};

use crate::features::billing::dto::*;
use crate::http::error::{ApiError, ApiResult};
use crate::http::extractors::{CurrentUser, IdempotencyKey, SignedWebhook};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/courses/{course_id}/checkout", post(checkout))
        .route("/me/purchases", get(my_purchases))
        .route("/me/purchases/{id}", get(get_purchase))
        .route("/webhooks/billing", post(billing_webhook))
}

/// Two layers of idempotency: Redis short-circuits exact replays (same key,
/// same body) with the stored response; the purchases table guarantees that
/// even without Redis one key maps to one purchase.
#[utoipa::path(post, path = "/api/v1/courses/{course_id}/checkout", tag = "billing", security(("bearer" = [])),
    params(("course_id" = CourseId, Path), ("Idempotency-Key" = String, Header)),
    responses((status = 201, body = CheckoutResponse), (status = 200, body = CheckoutResponse, description = "replayed"),
              (status = 409), (status = 422), (status = 503)))]
pub async fn checkout(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(course_id): Path<CourseId>,
    IdempotencyKey(key): IdempotencyKey,
) -> ApiResult<(StatusCode, Json<CheckoutResponse>)> {
    let route = format!("checkout:{course_id}");
    let user_key = user.id.to_string();
    // Per-user, not per-IP: a logged-in user hammering checkout is a client bug
    // or abuse either way; the provider call behind it is not free.
    if let RateLimitDecision::Limited { retry_after_secs } =
        state.rate_limiter.check("checkout", &user_key, 30, Duration::from_secs(3600)).await
    {
        return Err(ApiError::RateLimited { retry_after_secs });
    }
    let request_hash = courseflow_app::cache::IdempotencyGuard::hash_request(course_id.to_string().as_bytes());

    if state.idempotency.is_enabled() {
        match state.idempotency.begin(&user_key, &route, &key, &request_hash).await? {
            IdempotencyOutcome::Proceed => {}
            IdempotencyOutcome::Replay(stored) => {
                let body: CheckoutResponse =
                    serde_json::from_str(&stored.body).map_err(|e| ApiError::Internal(e.into()))?;
                return Ok((StatusCode::from_u16(stored.status).unwrap_or(StatusCode::OK), Json(body)));
            }
            IdempotencyOutcome::InProgress => {
                return Err(ApiError::Conflict("a request with this Idempotency-Key is in progress".into()));
            }
            IdempotencyOutcome::Mismatch => {
                return Err(ApiError::Validation(vec![crate::http::error::FieldError {
                    field: "Idempotency-Key".into(),
                    message: "key was already used with a different request".into(),
                }]));
            }
        }
    }

    let result = state.billing.start_checkout(&user.actor(), course_id, key.clone()).await;
    let started = match result {
        Ok(started) => started,
        Err(err) => {
            if matches!(err, AppError::Unavailable(_) | AppError::Internal(_) | AppError::Billing(_)) {
                state.idempotency.abandon(&user_key, &route, &key).await;
            }
            return Err(err.into());
        }
    };
    let status = if started.checkout_url.is_some() { StatusCode::CREATED } else { StatusCode::OK };
    let body = CheckoutResponse { purchase: started.purchase.into(), checkout_url: started.checkout_url };
    if state.idempotency.is_enabled() {
        let stored = StoredResponse {
            status: status.as_u16(),
            body: serde_json::to_string(&body).unwrap_or_default(),
            request_hash,
        };
        if let Err(err) = state.idempotency.finish(&user_key, &route, &key, stored).await {
            tracing::warn!(error = %err, "failed to store idempotent response");
        }
    }
    Ok((status, Json(body)))
}

#[utoipa::path(get, path = "/api/v1/me/purchases", tag = "billing", security(("bearer" = [])), responses((status = 200, body = Vec<PurchaseResponse>)))]
pub async fn my_purchases(State(state): State<AppState>, user: CurrentUser) -> ApiResult<Json<Vec<PurchaseResponse>>> {
    let list = state.billing.list_mine(&user.actor()).await?;
    Ok(Json(list.into_iter().map(Into::into).collect()))
}

#[utoipa::path(get, path = "/api/v1/me/purchases/{id}", tag = "billing", security(("bearer" = [])), params(("id" = PurchaseId, Path)),
    responses((status = 200, body = PurchaseResponse), (status = 404)))]
pub async fn get_purchase(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<PurchaseId>,
) -> ApiResult<Json<PurchaseResponse>> {
    Ok(Json(state.billing.get(&user.actor(), id).await?.into()))
}

/// Provider → CourseFlow. Always answers fast; the heavy lifting is one
/// short transaction, side effects go through the outbox.
#[utoipa::path(post, path = "/api/v1/webhooks/billing", tag = "billing", request_body = BillingWebhook,
    responses((status = 204, description = "applied or duplicate"), (status = 401, description = "bad signature")))]
pub async fn billing_webhook(
    State(state): State<AppState>,
    webhook: SignedWebhook<BillingWebhook>,
) -> ApiResult<StatusCode> {
    match state.billing.apply_event(&webhook.event_id, webhook.payload.event).await {
        Ok(_) => Ok(StatusCode::NO_CONTENT),
        // Duplicates and unknown payments are acknowledged so the provider
        // stops retrying; anything else surfaces as 5xx and will be retried.
        Err(AppError::Conflict(_)) | Err(AppError::NotFound { .. }) => Ok(StatusCode::NO_CONTENT),
        Err(err) => Err(err.into()),
    }
}
