//! Fixed-window counters in Redis: `INCR` + `EXPIRE` on first hit, executed
//! as one Lua script so that the window cannot be left without a TTL.

use std::time::Duration;

use crate::cache::RedisHandle;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RateLimitDecision {
    Allowed { remaining: u64 },
    Limited { retry_after_secs: u64 },
}

#[derive(Debug, Clone)]
pub struct RateLimiter {
    redis: Option<RedisHandle>,
    script: redis::Script,
    /// When Redis is unavailable: `true` lets requests through (availability
    /// first), `false` rejects them (protection first).
    fail_open: bool,
}

const SCRIPT: &str = r#"
local current = redis.call('INCR', KEYS[1])
if current == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
local ttl = redis.call('TTL', KEYS[1])
return {current, ttl}
"#;

impl RateLimiter {
    pub fn new(redis: Option<RedisHandle>, fail_open: bool) -> Self {
        Self { redis, script: redis::Script::new(SCRIPT), fail_open }
    }

    pub fn disabled() -> Self {
        Self::new(None, true)
    }

    /// `scope` names the protected action (`login`), `subject` who is being
    /// limited (an IP or a user id).
    pub async fn check(&self, scope: &str, subject: &str, limit: u64, window: Duration) -> RateLimitDecision {
        let Some(redis) = &self.redis else {
            return RateLimitDecision::Allowed { remaining: limit };
        };
        let key = redis.key(&["rl", scope, subject]);
        let mut conn = redis.conn();
        let result: Result<(u64, i64), redis::RedisError> =
            self.script.key(&key).arg(window.as_secs()).invoke_async(&mut conn).await;
        match result {
            Ok((count, ttl)) if count > limit => {
                metrics::counter!("courseflow_rate_limited_total", "scope" => scope.to_owned()).increment(1);
                RateLimitDecision::Limited { retry_after_secs: ttl.max(1) as u64 }
            }
            Ok((count, _)) => RateLimitDecision::Allowed { remaining: limit.saturating_sub(count) },
            Err(err) => {
                tracing::warn!(error = %err, scope, fail_open = self.fail_open, "rate limiter unavailable");
                if self.fail_open {
                    RateLimitDecision::Allowed { remaining: 0 }
                } else {
                    RateLimitDecision::Limited { retry_after_secs: 5 }
                }
            }
        }
    }
}
