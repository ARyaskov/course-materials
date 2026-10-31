//! Webhook signatures: `HMAC-SHA256(secret, "{timestamp}.{raw_body}")`,
//! transmitted as `X-Billing-Timestamp` and `X-Billing-Signature: v1=<hex>`.
//! Verification is constant-time and rejects stale timestamps.

use chrono::{DateTime, Utc};
use hmac::{Hmac, KeyInit, Mac};
use secrecy::{ExposeSecret, SecretString};
use sha2::Sha256;
use subtle::ConstantTimeEq;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum WebhookError {
    #[error("missing or malformed signature header")]
    MalformedSignature,
    #[error("missing or malformed timestamp header")]
    MalformedTimestamp,
    #[error("timestamp outside the replay window")]
    Stale,
    #[error("signature mismatch")]
    Mismatch,
}

pub fn sign_payload(secret: &SecretString, timestamp: i64, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.expose_secret().as_bytes())
        .unwrap_or_else(|_| unreachable!("HMAC accepts any key length"));
    mac.update(timestamp.to_string().as_bytes());
    mac.update(b".");
    mac.update(body);
    format!("v1={}", hex::encode(mac.finalize().into_bytes()))
}

#[derive(Clone)]
pub struct WebhookVerifier {
    secret: SecretString,
    replay_window_secs: i64,
}

impl std::fmt::Debug for WebhookVerifier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WebhookVerifier").field("replay_window_secs", &self.replay_window_secs).finish_non_exhaustive()
    }
}

impl WebhookVerifier {
    pub fn new(secret: SecretString, replay_window_secs: i64) -> Self {
        Self { secret, replay_window_secs }
    }

    pub fn verify(
        &self,
        timestamp_header: &str,
        signature_header: &str,
        body: &[u8],
        now: DateTime<Utc>,
    ) -> Result<(), WebhookError> {
        let timestamp: i64 = timestamp_header.trim().parse().map_err(|_| WebhookError::MalformedTimestamp)?;
        if (now.timestamp() - timestamp).abs() > self.replay_window_secs {
            return Err(WebhookError::Stale);
        }
        let provided = signature_header.strip_prefix("v1=").ok_or(WebhookError::MalformedSignature)?;
        let provided = hex::decode(provided).map_err(|_| WebhookError::MalformedSignature)?;
        let expected = sign_payload(&self.secret, timestamp, body);
        let expected = hex::decode(&expected[3..]).unwrap_or_default();
        if expected.ct_eq(&provided).into() { Ok(()) } else { Err(WebhookError::Mismatch) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_tamper() {
        let secret = SecretString::from("whsec_test");
        let v = WebhookVerifier::new(secret.clone(), 300);
        let now = Utc::now();
        let ts = now.timestamp();
        let body = br#"{"type":"payment_succeeded","provider_payment_id":"p1"}"#;
        let sig = sign_payload(&secret, ts, body);
        assert_eq!(v.verify(&ts.to_string(), &sig, body, now), Ok(()));
        assert_eq!(v.verify(&ts.to_string(), &sig, b"{}", now), Err(WebhookError::Mismatch));
        assert_eq!(v.verify(&(ts - 600).to_string(), &sig, body, now), Err(WebhookError::Stale));
        assert_eq!(v.verify(&ts.to_string(), "nope", body, now), Err(WebhookError::MalformedSignature));
    }
}
