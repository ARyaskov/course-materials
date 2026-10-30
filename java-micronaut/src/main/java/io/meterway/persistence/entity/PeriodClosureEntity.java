package io.meterway.persistence.entity;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

/** Журнал закрытий периода: делает операцию повторяемой без двойного выставления счетов. */
@Serdeable
@MappedEntity("period_closures")
public record PeriodClosureEntity(
        @Id UUID id,
        UUID tenantId,
        Instant periodStart,
        Instant periodEnd,
        String status,
        int invoiceCount,
        @Nullable Instant closedAt,
        @DateCreated Instant createdAt
) {
}
