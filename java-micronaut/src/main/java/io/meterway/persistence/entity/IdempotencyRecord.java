package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.EmbeddedId;
import io.micronaut.data.annotation.MappedEntity;

import java.time.Instant;
import java.util.UUID;

/**
 * Запись дедупликации. Составной ключ (tenantId, idempotencyKey) вынесен в {@link IdempotencyId}:
 * уникальность нужна глобальная, а таблица событий секционирована.
 */
@MappedEntity("ingest_idempotency")
public record IdempotencyRecord(
        @EmbeddedId IdempotencyId id,
        String bodyFingerprint,
        UUID eventId,
        Instant occurredAt,
        @DateCreated Instant createdAt
) {
}
