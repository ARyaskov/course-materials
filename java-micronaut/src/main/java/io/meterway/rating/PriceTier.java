package io.meterway.rating;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;

/**
 * Ступень прайса: полуинтервал [from, upTo) по количеству и цена за единицу в минорных единицах.
 * {@code upTo == null} — последняя, безграничная ступень.
 */
@Serdeable
public record PriceTier(
        BigDecimal from,
        @Nullable BigDecimal upTo,
        long unitPriceMinor,
        long flatFeeMinor,
        @Nullable BigDecimal packageSize
) {

    public PriceTier {
        if (from == null || from.signum() < 0) {
            throw new IllegalArgumentException("Нижняя граница ступени должна быть неотрицательной");
        }
        if (upTo != null && upTo.compareTo(from) <= 0) {
            throw new IllegalArgumentException("Верхняя граница ступени должна быть больше нижней: %s..%s".formatted(from, upTo));
        }
    }

    public static PriceTier of(long from, @Nullable Long upTo, long unitPriceMinor) {
        return new PriceTier(
                BigDecimal.valueOf(from),
                upTo == null ? null : BigDecimal.valueOf(upTo),
                unitPriceMinor,
                0L,
                null
        );
    }

    public boolean isUnbounded() {
        return upTo == null;
    }
}
