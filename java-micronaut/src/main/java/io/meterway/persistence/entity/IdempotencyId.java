package io.meterway.persistence.entity;

import io.micronaut.data.annotation.Embeddable;

import java.util.UUID;

@Embeddable
public record IdempotencyId(UUID tenantId, String idempotencyKey) {
}
