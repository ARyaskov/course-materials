package io.meterway.audit;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.data.annotation.TypeDef;
import io.micronaut.data.model.DataType;
import io.micronaut.serde.annotation.Serdeable;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@Serdeable
@MappedEntity("audit_entries")
public record AuditEntry(
        @Id UUID id,
        @Nullable UUID tenantId,
        String principal,
        String action,
        String outcome,
        @Nullable String failure,
        @TypeDef(type = DataType.JSON) Map<String, Object> details,
        Instant occurredAt
) {
}
