package io.meterway.persistence.entity;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

@Serdeable
@MappedEntity("quota_policies")
public record QuotaPolicyEntity(
        @Id UUID id,
        UUID tenantId,
        @Nullable UUID customerId,
        String meterCode,
        String windowSpec,
        long limitValue,
        String action,
        boolean enabled,
        @DateCreated Instant createdAt
) {
}
