package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.UUID;

@Serdeable
@MappedEntity("customers")
public record CustomerEntity(
        @Id UUID id,
        UUID tenantId,
        String externalRef,
        String name,
        String currency,
        @DateCreated Instant createdAt
) {
    public static CustomerEntity create(UUID tenantId, String externalRef, String name, String currency) {
        return new CustomerEntity(UUID.randomUUID(), tenantId, externalRef, name, currency, null);
    }
}
