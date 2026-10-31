//! Verifies the provider signature over the *raw* body before any parsing.
//! Parsing first would let an attacker probe the JSON schema of an
//! endpoint that should not even talk to them.

use axum::body::Bytes;
use axum::extract::{FromRef, FromRequest, Request};
use courseflow_app::billing::WebhookVerifier;
use courseflow_app::billing::webhook::WebhookError;
use serde::de::DeserializeOwned;

use crate::http::error::ApiError;
use crate::state::AppState;

pub const TIMESTAMP_HEADER: &str = "x-billing-timestamp";
pub const SIGNATURE_HEADER: &str = "x-billing-signature";
pub const EVENT_ID_HEADER: &str = "x-billing-event-id";

#[derive(Debug)]
pub struct SignedWebhook<T> {
    pub event_id: String,
    pub payload: T,
}

impl FromRef<AppState> for WebhookVerifier {
    fn from_ref(state: &AppState) -> Self {
        state.webhook_verifier.clone()
    }
}

impl<T, S> FromRequest<S> for SignedWebhook<T>
where
    T: DeserializeOwned,
    S: Send + Sync,
    WebhookVerifier: FromRef<S>,
{
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let headers = req.headers().clone();
        let header = |name: &str| {
            headers
                .get(name)
                .and_then(|v| v.to_str().ok())
                .map(str::to_owned)
                .ok_or(ApiError::Unauthorized("missing webhook header"))
        };
        let timestamp = header(TIMESTAMP_HEADER)?;
        let signature = header(SIGNATURE_HEADER)?;
        let event_id = header(EVENT_ID_HEADER)?;
        let verifier = WebhookVerifier::from_ref(state);

        let body = Bytes::from_request(req, state).await.map_err(|e| ApiError::BadRequest(e.body_text()))?;
        verifier.verify(&timestamp, &signature, &body, chrono::Utc::now()).map_err(|e| match e {
            WebhookError::Stale => ApiError::Unauthorized("webhook timestamp outside replay window"),
            WebhookError::Mismatch => ApiError::Unauthorized("webhook signature mismatch"),
            _ => ApiError::Unauthorized("malformed webhook signature"),
        })?;
        let payload = serde_json::from_slice::<T>(&body)
            .map_err(|e| ApiError::BadRequest(format!("malformed webhook payload: {e}")))?;
        Ok(SignedWebhook { event_id, payload })
    }
}
