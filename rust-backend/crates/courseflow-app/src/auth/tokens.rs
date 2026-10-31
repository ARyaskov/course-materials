//! Opaque random secrets: refresh tokens, password-reset and e-mail
//! verification tokens. Only the SHA-256 digest is ever stored.

use rand::{Rng, RngExt};
use sha2::{Digest, Sha256};

/// 32 random bytes, base64url without padding → 43 characters.
pub fn generate_secret() -> String {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    base64::Engine::encode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, bytes)
}

pub fn digest(secret: &str) -> Vec<u8> {
    Sha256::digest(secret.as_bytes()).to_vec()
}

/// Human-visible certificate code such as `CF-7Q2M-9K1X`.
pub(crate) fn certificate_code() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    let mut out = String::from("CF-");
    for i in 0..8 {
        if i == 4 {
            out.push('-');
        }
        let idx = rng.random_range(0..ALPHABET.len());
        out.push(ALPHABET[idx] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secrets_are_unique_and_long() {
        let a = generate_secret();
        let b = generate_secret();
        assert_ne!(a, b);
        assert_eq!(a.len(), 43);
        assert_eq!(digest(&a).len(), 32);
    }

    #[test]
    fn certificate_code_shape() {
        let code = certificate_code();
        assert_eq!(code.len(), 12);
        assert!(code.starts_with("CF-"));
    }
}
