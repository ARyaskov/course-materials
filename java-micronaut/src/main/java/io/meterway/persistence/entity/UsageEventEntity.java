package io.meterway.persistence.entity;

import io.micronaut.data.annotation.DateCreated;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Сырое событие потребления. Таблица секционирована по {@code occurred_at},
 * поэтому идентификатор генерируется на стороне приложения: время-упорядоченный UUID
 * даёт локальность записи внутри секции.
 */
@Serdeable
@MappedEntity("usage_events")
public record UsageEventEntity(
        @Id UUID id,
        UUID tenantId,
        UUID customerId,
        String meterCode,
        Instant occurredAt,
        @DateCreated Instant receivedAt,
        BigDecimal quantity,
        @TypeDef(type = DataType.JSON) Map<String, Object> properties,
        String source
) {
}
