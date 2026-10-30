package io.meterway.persistence.entity;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.Version;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

@Serdeable
@MappedEntity("invoices")
public record InvoiceEntity(
        @Id UUID id,
        UUID tenantId,
        UUID customerId,
        UUID subscriptionId,
        Instant periodStart,
        Instant periodEnd,
        String currency,
        long totalMinor,
        String status,
        @Nullable Instant issuedAt,
        @Version Long version,
        @DateCreated Instant createdAt
) {
}
