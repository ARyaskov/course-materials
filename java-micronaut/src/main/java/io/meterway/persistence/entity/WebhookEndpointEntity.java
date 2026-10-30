package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;

import java.time.Instant;
import java.util.UUID;

@MappedEntity("webhook_endpoints")
public record WebhookEndpointEntity(
        @Id UUID id,
        UUID tenantId,
        String url,
        String secret,
        @TypeDef(type = DataType.STRING_ARRAY) String[] eventTypes,
        boolean active,
        @DateCreated Instant createdAt
) {
}
