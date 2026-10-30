package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

@Serdeable
@MappedEntity("tenants")
public record TenantEntity(
        @Id UUID id,
        String name,
        @DateCreated Instant createdAt
) {
    public static TenantEntity create(UUID id, String name) {
        return new TenantEntity(id, name, null);
    }
}
