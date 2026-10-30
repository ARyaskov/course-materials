package io.meterway.domain;

import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneOffset;

/**
 * Полуинтервал [start, end) расчётного периода. Границы всегда в UTC:
 * событие принадлежит периоду по {@code occurredAt}, а не по времени приёма.
 */
@Serdeable
public record BillingPeriod(Instant start, Instant end) {

    public BillingPeriod {
        if (!start.isBefore(end)) {
            throw new IllegalArgumentException("Начало периода должно быть строго раньше конца: %s..%s".formatted(start, end));
        }
    }

    public static BillingPeriod ofMonth(YearMonth month) {
        LocalDate first = month.atDay(1);
        return new BillingPeriod(
                first.atStartOfDay(ZoneOffset.UTC).toInstant(),
                first.plusMonths(1).atStartOfDay(ZoneOffset.UTC).toInstant()
        );
    }

    public static BillingPeriod monthOf(Instant moment) {
        return ofMonth(YearMonth.from(moment.atOffset(ZoneOffset.UTC)));
    }

    public boolean contains(Instant moment) {
        return !moment.isBefore(start) && moment.isBefore(end);
    }

    public String label() {
        return YearMonth.from(start.atOffset(ZoneOffset.UTC)).toString();
    }
}
