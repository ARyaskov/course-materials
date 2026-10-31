//! Short-lived access tokens (jsonwebtoken 11, HS256). The refresh token is
//! not a JWT: it is an opaque secret whose hash lives in PostgreSQL.

use std::time::Duration;

use chrono::{DateTime, Utc};
use courseflow_core::ids::UserId;
use courseflow_core::users::Role;
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation};
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AccessClaims {
    /// Subject: the user id.
    pub sub: UserId,
    pub role: Role,
    /// Token type guard: an access token must never be accepted where a
    /// different token kind is expected.
    pub typ: String,
    pub iat: i64,
    pub exp: i64,
    /// Unique token id: lets a token be denylisted if ever needed.
    pub jti: Uuid,
}

#[derive(Debug, thiserror::Error)]
pub enum JwtError {
    #[error("token expired")]
    Expired,
    #[error("invalid token")]
    Invalid,
}

#[derive(Clone)]
pub struct JwtSigner {
    encoding: EncodingKey,
    decoding: DecodingKey,
    validation: Validation,
    access_ttl: Duration,
}

impl std::fmt::Debug for JwtSigner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("JwtSigner").field("access_ttl", &self.access_ttl).finish_non_exhaustive()
    }
}

impl JwtSigner {
    pub fn new(secret: &SecretString, access_ttl: Duration) -> Self {
        let bytes = secret.expose_secret().as_bytes();
        let mut validation = Validation::new(Algorithm::HS256);
        validation.leeway = 5;
        validation.set_required_spec_claims(&["exp", "iat"]);
        Self {
            encoding: EncodingKey::from_secret(bytes),
            decoding: DecodingKey::from_secret(bytes),
            validation,
            access_ttl,
        }
    }

    pub fn access_ttl(&self) -> Duration {
        self.access_ttl
    }

    pub fn issue(&self, user: UserId, role: Role, now: DateTime<Utc>) -> Result<String, jsonwebtoken::errors::Error> {
        let claims = AccessClaims {
            sub: user,
            role,
            typ: "access".to_owned(),
            iat: now.timestamp(),
            exp: (now + self.access_ttl).timestamp(),
            jti: Uuid::now_v7(),
        };
        jsonwebtoken::encode(&Header::new(Algorithm::HS256), &claims, &self.encoding)
    }

    pub fn verify(&self, token: &str) -> Result<AccessClaims, JwtError> {
        let data =
            jsonwebtoken::decode::<AccessClaims>(token, &self.decoding, &self.validation).map_err(|e| {
                match e.kind() {
                    jsonwebtoken::errors::ErrorKind::ExpiredSignature => JwtError::Expired,
                    _ => JwtError::Invalid,
                }
            })?;
        if data.claims.typ != "access" {
            return Err(JwtError::Invalid);
        }
        Ok(data.claims)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signer(ttl: Duration) -> JwtSigner {
        JwtSigner::new(&SecretString::from("test-secret-with-at-least-32-bytes!!"), ttl)
    }

    #[test]
    fn issue_and_verify() {
        let s = signer(Duration::from_secs(60));
        let user = UserId::new();
        let token = s.issue(user, Role::Author, Utc::now()).unwrap();
        let claims = s.verify(&token).unwrap();
        assert_eq!(claims.sub, user);
        assert_eq!(claims.role, Role::Author);
    }

    #[test]
    fn expired_token_is_rejected() {
        let s = signer(Duration::from_secs(60));
        let token = s.issue(UserId::new(), Role::Student, Utc::now() - chrono::Duration::minutes(10)).unwrap();
        assert!(matches!(s.verify(&token), Err(JwtError::Expired)));
    }

    #[test]
    fn other_secret_is_rejected() {
        let a = signer(Duration::from_secs(60));
        let b = JwtSigner::new(&SecretString::from("another-secret-with-at-least-32-bytes"), Duration::from_secs(60));
        let token = a.issue(UserId::new(), Role::Student, Utc::now()).unwrap();
        assert!(matches!(b.verify(&token), Err(JwtError::Invalid)));
    }
}
