package io.meterway.persistence.entity;

import io.meterway.domain.AggregationType;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateUpdated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.Version;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * Агрегат потребления за окно. {@code @Version} включает оптимистичную блокировку:
 * два консьюмера, обновляющие один агрегат, не затрут друг друга молча.
 */
@Serdeable
@MappedEntity("usage_aggregates")
public record UsageAggregateEntity(
        @Id UUID id,
        UUID tenantId,
        UUID customerId,
        String meterCode,
        Instant periodStart,
        Instant periodEnd,
        AggregationType aggregation,
        BigDecimal value,
        long eventCount,
        @Nullable Instant lastEventAt,
        @DateUpdated Instant updatedAt,
        @Version Long version
) {
}
