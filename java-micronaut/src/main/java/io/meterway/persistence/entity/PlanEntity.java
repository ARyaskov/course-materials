package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

@Serdeable
@MappedEntity("plans")
public record PlanEntity(
        @Id UUID id,
        UUID tenantId,
        String code,
        String name,
        String currency,
        long fixedFeeMinor,
        boolean active,
        @DateCreated Instant createdAt
) {
}
