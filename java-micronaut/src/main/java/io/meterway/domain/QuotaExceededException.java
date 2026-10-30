package io.meterway.domain;

public class QuotaExceededException extends MeterwayException {

    private final String meterCode;
    private final long limit;
    private final long used;
    private final long retryAfterSeconds;

    public QuotaExceededException(String meterCode, long limit, long used, long retryAfterSeconds) {
        super("Квота по метрике %s исчерпана: %d из %d".formatted(meterCode, used, limit));
        this.meterCode = meterCode;
        this.limit = limit;
        this.used = used;
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public String meterCode() {
        return meterCode;
    }

    public long limit() {
        return limit;
    }

    public long used() {
        return used;
    }

    public long retryAfterSeconds() {
        return retryAfterSeconds;
    }

    @Override
    public String problemType() {
        return "quota-exceeded";
    }
}
