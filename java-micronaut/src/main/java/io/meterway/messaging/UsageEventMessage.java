package io.meterway.messaging;

import io.meterway.persistence.entity.UsageEventEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Сообщение о принятом событии. Отдельный тип, а не сущность:
 * схема топика живёт своей жизнью и не должна меняться от переименования колонки.
 */
@Serdeable
public record UsageEventMessage(
        UUID eventId,
        UUID tenantId,
        UUID customerId,
        String meterCode,
        Instant occurredAt,
        BigDecimal quantity,
        Map<String, Object> properties,
        int schemaVersion
) {

    public static final int CURRENT_SCHEMA_VERSION = 1;

    public static UsageEventMessage from(UsageEventEntity entity) {
        return new UsageEventMessage(
                entity.id(),
                entity.tenantId(),
                entity.customerId(),
                entity.meterCode(),
                entity.occurredAt(),
                entity.quantity(),
                entity.properties(),
                CURRENT_SCHEMA_VERSION);
    }

    /**
     * Ключ партиционирования. События одного клиента по одной метрике должны идти
     * в одну партицию: иначе инкрементальная агрегация теряет порядок.
     */
    public String partitionKey() {
        return tenantId + ":" + customerId + ":" + meterCode;
    }
}
