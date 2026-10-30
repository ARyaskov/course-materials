package io.meterway.ratelimit;

import io.meterway.domain.MeterwayException;

/**
 * Превышение технического лимита частоты.
 * <p>
 * Отличается от {@code QuotaExceededException}: там исчерпан оплаченный объём,
 * здесь — частота обращений. Для клиента это разные ситуации с разными действиями,
 * поэтому и тип проблемы разный.
 */
public class RateLimitExceededException extends MeterwayException {

    private final String policy;
    private final int limit;
    private final long retryAfterSeconds;

    public RateLimitExceededException(String policy, int limit, long retryAfterSeconds) {
        super("Превышен лимит обращений по политике %s: %d за окно".formatted(policy, limit));
        this.policy = policy;
        this.limit = limit;
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public String policy() {
        return policy;
    }

    public int limit() {
        return limit;
    }

    public long retryAfterSeconds() {
        return retryAfterSeconds;
    }

    @Override
    public String problemType() {
        return "rate-limit-exceeded";
    }
}
