package io.meterway.persistence.repository;

import io.micronaut.core.annotation.Introspected;
import io.micronaut.core.annotation.Nullable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * Проекция агрегирующего запроса. {@code @Introspected} обязателен:
 * Micronaut Data собирает объект по метаданным конструктора, а не рефлексией.
 */
@Introspected
public record UsageRollup(
        UUID tenantId,
        UUID customerId,
        String meterCode,
        BigDecimal sumValue,
        BigDecimal maxValue,
        long eventCount,
        @Nullable Instant lastEventAt
) {
}
