package io.meterway.quota;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;

/**
 * Окно квоты. Фиксированное окно выбрано осознанно: скользящее требует хранить историю
 * обращений, а на частоте ingest это заметная память в Redis ради точности,
 * которая никому в тарификации не нужна.
 */
public enum QuotaWindow {

    MINUTE(ChronoUnit.MINUTES, Duration.ofMinutes(2)),
    HOUR(ChronoUnit.HOURS, Duration.ofHours(2)),
    DAY(ChronoUnit.DAYS, Duration.ofDays(2)),
    MONTH(ChronoUnit.MONTHS, Duration.ofDays(35));

    private final ChronoUnit unit;
    private final Duration keyTtl;

    QuotaWindow(ChronoUnit unit, Duration keyTtl) {
        this.unit = unit;
        this.keyTtl = keyTtl;
    }

    public static QuotaWindow parse(String spec) {
        return valueOf(spec.trim().toUpperCase(java.util.Locale.ROOT));
    }

    /** Начало окна, в которое попадает момент. Для MONTH усечение делается через YearMonth. */
    public Instant windowStart(Instant moment) {
        if (this == MONTH) {
            return java.time.YearMonth.from(moment.atOffset(java.time.ZoneOffset.UTC))
                    .atDay(1).atStartOfDay(java.time.ZoneOffset.UTC).toInstant();
        }
        return moment.truncatedTo(unit);
    }

    public Instant windowEnd(Instant moment) {
        Instant start = windowStart(moment);
        return this == MONTH
                ? start.atOffset(java.time.ZoneOffset.UTC).plusMonths(1).toInstant()
                : start.plus(1, unit);
    }

    public Duration keyTtl() {
        return keyTtl;
    }

    /**
     * Секунды до сброса окна, округлённые вверх.
     * Усечение вниз даёт заголовок {@code Retry-After}, по которому клиент повторит запрос
     * на доли секунды раньше сброса и снова получит 429.
     */
    public long secondsUntilReset(Instant moment) {
        Duration remaining = Duration.between(moment, windowEnd(moment));
        return remaining.getNano() > 0 ? remaining.toSeconds() + 1 : remaining.toSeconds();
    }
}
