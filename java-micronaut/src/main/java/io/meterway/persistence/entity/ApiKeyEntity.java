package io.meterway.persistence.entity;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;

import java.time.Instant;
import java.util.UUID;

@MappedEntity("api_keys")
public record ApiKeyEntity(
        @Id UUID id,
        UUID tenantId,
        String keyPrefix,
        String secretHash,
        String label,
        @TypeDef(type = DataType.STRING_ARRAY) String[] scopes,
        @DateCreated Instant createdAt,
        @Nullable Instant revokedAt
) {
    public boolean isActive() {
        return revokedAt == null;
    }
}
