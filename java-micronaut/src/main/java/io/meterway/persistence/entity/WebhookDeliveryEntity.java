package io.meterway.persistence.entity;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@MappedEntity("webhook_deliveries")
public record WebhookDeliveryEntity(
        @Id UUID id,
        UUID endpointId,
        String eventType,
        @TypeDef(type = DataType.JSON) Map<String, Object> payload,
        String status,
        int attempts,
        Instant nextAttemptAt,
        @Nullable String lastError,
        @DateCreated Instant createdAt,
        @Nullable Instant deliveredAt
) {
}
