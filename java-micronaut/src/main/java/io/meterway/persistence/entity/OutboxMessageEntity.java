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

/** Строка transactional outbox: пишется той же транзакцией, что и изменение состояния. */
@MappedEntity("outbox_messages")
public record OutboxMessageEntity(
        @Id UUID id,
        String aggregateType,
        String aggregateId,
        String eventType,
        @TypeDef(type = DataType.JSON) Map<String, Object> payload,
        @DateCreated Instant createdAt,
        @Nullable Instant publishedAt
) {
}
