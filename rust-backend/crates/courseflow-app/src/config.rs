//! Configuration is read once, at startup, from `COURSEFLOW_*` environment
//! variables. A missing or malformed value is a startup failure, never a
//! runtime surprise.

use std::net::SocketAddr;
use std::time::Duration;

use secrecy::SecretString;

#[derive(Debug, Clone)]
pub struct Config {
    pub http: HttpConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub auth: AuthConfig,
    pub billing: BillingConfig,
    pub worker: WorkerConfig,
    /// Base URL that external systems use to reach this API (webhook callbacks, links in e-mails).
    pub public_base_url: String,
    pub environment: Environment,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Environment {
    Local,
    Test,
    Production,
}

impl Environment {
    pub fn is_production(self) -> bool {
        self == Environment::Production
    }
}

#[derive(Debug, Clone)]
pub struct HttpConfig {
    pub addr: SocketAddr,
    pub request_timeout: Duration,
    pub body_limit_bytes: usize,
    pub shutdown_timeout: Duration,
    pub cors_allowed_origins: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    pub url: SecretString,
    pub max_connections: u32,
    pub min_connections: u32,
    pub acquire_timeout: Duration,
    pub statement_timeout: Duration,
}

#[derive(Debug, Clone)]
pub struct RedisConfig {
    pub url: SecretString,
    pub key_prefix: String,
}

#[derive(Debug, Clone)]
pub struct AuthConfig {
    pub jwt_secret: SecretString,
    pub access_ttl: Duration,
    pub refresh_ttl: Duration,
    pub action_token_ttl: Duration,
    pub argon2_memory_kib: u32,
    pub argon2_iterations: u32,
    pub argon2_parallelism: u32,
}

#[derive(Debug, Clone)]
pub struct BillingConfig {
    pub base_url: String,
    pub api_key: SecretString,
    pub webhook_secret: SecretString,
    pub timeout: Duration,
    pub max_retries: u32,
}

#[derive(Debug, Clone)]
pub struct WorkerConfig {
    pub outbox_batch_size: i64,
    pub outbox_poll_interval: Duration,
    pub outbox_max_attempts: i32,
    pub cleanup_interval: Duration,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("missing required environment variable {0}")]
    Missing(&'static str),
    #[error("environment variable {name} has invalid value: {reason}")]
    Invalid { name: &'static str, reason: String },
}

impl Config {
    /// Reads configuration from the process environment. Call `dotenvy::dotenv()`
    /// before this in local development; never in production images.
    pub fn from_env() -> Result<Self, ConfigError> {
        let environment = match optional("COURSEFLOW_ENV")?.as_deref() {
            None | Some("local") => Environment::Local,
            Some("test") => Environment::Test,
            Some("production") | Some("prod") => Environment::Production,
            Some(other) => {
                return Err(ConfigError::Invalid {
                    name: "COURSEFLOW_ENV",
                    reason: format!("unknown environment {other}"),
                });
            }
        };

        let config = Self {
            http: HttpConfig {
                addr: parse("COURSEFLOW_HTTP_ADDR", "127.0.0.1:8080")?,
                request_timeout: seconds("COURSEFLOW_HTTP_REQUEST_TIMEOUT_SECS", 30)?,
                body_limit_bytes: parse("COURSEFLOW_HTTP_BODY_LIMIT_BYTES", "1048576")?,
                shutdown_timeout: seconds("COURSEFLOW_SHUTDOWN_TIMEOUT_SECS", 20)?,
                cors_allowed_origins: optional("COURSEFLOW_CORS_ALLOWED_ORIGINS")?
                    .map(|v| v.split(',').map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).collect())
                    .unwrap_or_default(),
            },
            database: DatabaseConfig {
                url: secret("COURSEFLOW_DATABASE_URL")?,
                max_connections: parse("COURSEFLOW_DB_MAX_CONNECTIONS", "10")?,
                min_connections: parse("COURSEFLOW_DB_MIN_CONNECTIONS", "1")?,
                acquire_timeout: seconds("COURSEFLOW_DB_ACQUIRE_TIMEOUT_SECS", 5)?,
                statement_timeout: seconds("COURSEFLOW_DB_STATEMENT_TIMEOUT_SECS", 10)?,
            },
            redis: RedisConfig {
                url: secret("COURSEFLOW_REDIS_URL")?,
                key_prefix: optional("COURSEFLOW_REDIS_KEY_PREFIX")?.unwrap_or_else(|| "cf".to_owned()),
            },
            auth: AuthConfig {
                jwt_secret: secret("COURSEFLOW_JWT_SECRET")?,
                access_ttl: seconds("COURSEFLOW_ACCESS_TTL_SECS", 900)?,
                refresh_ttl: seconds("COURSEFLOW_REFRESH_TTL_SECS", 30 * 24 * 3600)?,
                action_token_ttl: seconds("COURSEFLOW_ACTION_TOKEN_TTL_SECS", 3600)?,
                argon2_memory_kib: parse("COURSEFLOW_ARGON2_MEMORY_KIB", "19456")?,
                argon2_iterations: parse("COURSEFLOW_ARGON2_ITERATIONS", "2")?,
                argon2_parallelism: parse("COURSEFLOW_ARGON2_PARALLELISM", "1")?,
            },
            billing: BillingConfig {
                base_url: optional("COURSEFLOW_BILLING_BASE_URL")?
                    .unwrap_or_else(|| "http://127.0.0.1:8090".to_owned()),
                api_key: optional("COURSEFLOW_BILLING_API_KEY")?
                    .map(SecretString::from)
                    .unwrap_or_else(|| SecretString::from("dev-api-key")),
                webhook_secret: secret("COURSEFLOW_BILLING_WEBHOOK_SECRET")?,
                timeout: seconds("COURSEFLOW_BILLING_TIMEOUT_SECS", 5)?,
                max_retries: parse("COURSEFLOW_BILLING_MAX_RETRIES", "3")?,
            },
            worker: WorkerConfig {
                outbox_batch_size: parse("COURSEFLOW_OUTBOX_BATCH_SIZE", "50")?,
                outbox_poll_interval: seconds("COURSEFLOW_OUTBOX_POLL_INTERVAL_SECS", 2)?,
                outbox_max_attempts: parse("COURSEFLOW_OUTBOX_MAX_ATTEMPTS", "8")?,
                cleanup_interval: seconds("COURSEFLOW_CLEANUP_INTERVAL_SECS", 600)?,
            },
            public_base_url: optional("COURSEFLOW_PUBLIC_BASE_URL")?
                .unwrap_or_else(|| "http://127.0.0.1:8080".to_owned()),
            environment,
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), ConfigError> {
        use secrecy::ExposeSecret;
        if self.auth.jwt_secret.expose_secret().len() < 32 {
            return Err(ConfigError::Invalid {
                name: "COURSEFLOW_JWT_SECRET",
                reason: "must be at least 32 bytes".into(),
            });
        }
        if self.database.min_connections > self.database.max_connections {
            return Err(ConfigError::Invalid {
                name: "COURSEFLOW_DB_MIN_CONNECTIONS",
                reason: "must not exceed max connections".into(),
            });
        }
        if self.environment.is_production() && self.auth.jwt_secret.expose_secret().starts_with("dev-") {
            return Err(ConfigError::Invalid {
                name: "COURSEFLOW_JWT_SECRET",
                reason: "development secret in production".into(),
            });
        }
        Ok(())
    }
}

impl Config {
    /// Deterministic configuration for tests: no environment, no secrets
    /// from disk, fast Argon2 parameters.
    pub fn for_tests(database_url: &str) -> Self {
        Self {
            http: HttpConfig {
                addr: "127.0.0.1:0".parse().unwrap_or_else(|_| unreachable!()),
                request_timeout: Duration::from_secs(5),
                body_limit_bytes: 1024 * 1024,
                shutdown_timeout: Duration::from_secs(1),
                cors_allowed_origins: vec![],
            },
            database: DatabaseConfig {
                url: SecretString::from(database_url.to_owned()),
                max_connections: 5,
                min_connections: 0,
                acquire_timeout: Duration::from_secs(5),
                statement_timeout: Duration::from_secs(5),
            },
            redis: RedisConfig {
                url: SecretString::from("redis://127.0.0.1:6379/15"),
                key_prefix: "cftest".to_owned(),
            },
            auth: AuthConfig {
                jwt_secret: SecretString::from("test-only-jwt-secret-with-32-bytes-min!!"),
                access_ttl: Duration::from_secs(300),
                refresh_ttl: Duration::from_secs(3600),
                action_token_ttl: Duration::from_secs(600),
                argon2_memory_kib: 1024,
                argon2_iterations: 1,
                argon2_parallelism: 1,
            },
            billing: BillingConfig {
                base_url: "http://127.0.0.1:1".to_owned(),
                api_key: SecretString::from("test-api-key"),
                webhook_secret: SecretString::from("test-webhook-secret"),
                timeout: Duration::from_millis(500),
                max_retries: 2,
            },
            worker: WorkerConfig {
                outbox_batch_size: 10,
                outbox_poll_interval: Duration::from_millis(50),
                outbox_max_attempts: 3,
                cleanup_interval: Duration::from_secs(60),
            },
            public_base_url: "http://127.0.0.1:8080".to_owned(),
            environment: Environment::Test,
        }
    }
}

fn optional(name: &'static str) -> Result<Option<String>, ConfigError> {
    match std::env::var(name) {
        Ok(v) if v.trim().is_empty() => Ok(None),
        Ok(v) => Ok(Some(v)),
        Err(std::env::VarError::NotPresent) => Ok(None),
        Err(std::env::VarError::NotUnicode(_)) => Err(ConfigError::Invalid { name, reason: "not valid UTF-8".into() }),
    }
}

fn required(name: &'static str) -> Result<String, ConfigError> {
    optional(name)?.ok_or(ConfigError::Missing(name))
}

fn secret(name: &'static str) -> Result<SecretString, ConfigError> {
    required(name).map(SecretString::from)
}

fn parse<T: std::str::FromStr>(name: &'static str, default: &str) -> Result<T, ConfigError>
where
    T::Err: std::fmt::Display,
{
    let raw = optional(name)?.unwrap_or_else(|| default.to_owned());
    raw.parse::<T>().map_err(|e| ConfigError::Invalid { name, reason: e.to_string() })
}

fn seconds(name: &'static str, default: u64) -> Result<Duration, ConfigError> {
    parse::<u64>(name, &default.to_string()).map(Duration::from_secs)
}
