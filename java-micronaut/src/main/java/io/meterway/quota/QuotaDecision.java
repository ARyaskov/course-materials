package io.meterway.quota;

import io.micronaut.serde.annotation.Serdeable;

/** Итог проверки квоты. {@code limit == -1} означает, что политика не настроена. */
@Serdeable
public record QuotaDecision(boolean allowed, String meterCode, long limit, long used, long resetInSeconds) {

    public static QuotaDecision unlimited(String meterCode) {
        return new QuotaDecision(true, meterCode, -1L, 0L, 0L);
    }

    public long remaining() {
        return limit < 0 ? Long.MAX_VALUE : Math.max(0L, limit - used);
    }
}
