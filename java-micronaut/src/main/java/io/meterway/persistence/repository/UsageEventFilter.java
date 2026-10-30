package io.meterway.persistence.repository;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Набор необязательных условий поиска событий. Тенант сюда не входит: он берётся из Authentication. */
@Serdeable
public record UsageEventFilter(
        @Nullable UUID customerId,
        @Nullable List<String> meterCodes,
        @Nullable Instant from,
        @Nullable Instant to,
        @Nullable BigDecimal minQuantity,
        @Nullable String source
) {

    public static UsageEventFilter empty() {
        return new UsageEventFilter(null, null, null, null, null, null);
    }
}
