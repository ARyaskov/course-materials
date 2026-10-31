//! Argon2id password hashing (argon2 0.6). Hashing takes ~50–100 ms by design,
//! so both operations run on Tokio's blocking pool instead of a worker thread.

use argon2::{Algorithm, Argon2, Params, PasswordHasher as _, PasswordVerifier as _, Version};
use courseflow_core::ports::{BoxFuture, HashError, PasswordHasher};
use courseflow_core::users::PasswordHash;

use crate::config::AuthConfig;

#[derive(Debug, Clone)]
pub struct Argon2Hasher {
    params: Params,
}

impl Argon2Hasher {
    /// OWASP (2026) baseline for Argon2id: 19 MiB memory, 2 iterations, 1 lane.
    pub fn from_config(config: &AuthConfig) -> Result<Self, HashError> {
        let params = Params::new(config.argon2_memory_kib, config.argon2_iterations, config.argon2_parallelism, None)
            .map_err(|e| HashError(e.to_string()))?;
        Ok(Self { params })
    }

    /// Cheap parameters for tests: still real Argon2id, just fast.
    pub fn insecure_for_tests() -> Self {
        Self { params: Params::new(1024, 1, 1, None).unwrap_or_default() }
    }

    fn engine(&self) -> Argon2<'static> {
        Argon2::new(Algorithm::Argon2id, Version::V0x13, self.params.clone())
    }
}

impl PasswordHasher for Argon2Hasher {
    fn hash<'a>(&'a self, password: &'a str) -> BoxFuture<'a, Result<PasswordHash, HashError>> {
        let engine = self.engine();
        let password = password.to_owned();
        Box::pin(async move {
            tokio::task::spawn_blocking(move || {
                engine
                    .hash_password(password.as_bytes())
                    .map(|phc| PasswordHash::from_phc(phc.to_string()))
                    .map_err(|e| HashError(e.to_string()))
            })
            .await
            .map_err(|e| HashError(format!("hashing task failed: {e}")))?
        })
    }

    fn verify<'a>(&'a self, password: &'a str, hash: &'a PasswordHash) -> BoxFuture<'a, Result<bool, HashError>> {
        let engine = self.engine();
        let password = password.to_owned();
        let phc = hash.as_phc().to_owned();
        Box::pin(async move {
            tokio::task::spawn_blocking(move || match engine.verify_password(password.as_bytes(), phc.as_str()) {
                Ok(()) => Ok(true),
                Err(argon2::password_hash::Error::PasswordInvalid) => Ok(false),
                Err(e) => Err(HashError(e.to_string())),
            })
            .await
            .map_err(|e| HashError(format!("verification task failed: {e}")))?
        })
    }

    /// Hash parameters may be raised over time; a stored hash made with weaker
    /// parameters should be recomputed on the next successful login.
    fn needs_rehash(&self, hash: &PasswordHash) -> bool {
        match argon2::password_hash::phc::PasswordHash::new(hash.as_phc()) {
            Ok(parsed) => Params::try_from(&parsed)
                .map(|p| {
                    p.m_cost() != self.params.m_cost()
                        || p.t_cost() != self.params.t_cost()
                        || p.p_cost() != self.params.p_cost()
                })
                .unwrap_or(true),
            Err(_) => true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn hash_and_verify_round_trip() {
        let hasher = Argon2Hasher::insecure_for_tests();
        let hash = hasher.hash("correct-horse-42").await.unwrap();
        assert!(hash.as_phc().starts_with("$argon2id$"));
        assert!(hasher.verify("correct-horse-42", &hash).await.unwrap());
        assert!(!hasher.verify("wrong-horse-42", &hash).await.unwrap());
        assert!(!hasher.needs_rehash(&hash));
    }
}
