package io.meterway.ingest;

import io.meterway.validation.ValidMeterCode;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.serde.annotation.Serdeable;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;

/**
 * Одно событие потребления во входном формате.
 * Ключ идемпотентности задаёт источник: только он знает, что «то же самое событие»
 * уже отправлялось после сетевого таймаута.
 */
@Serdeable
public record UsageEventRequest(

        @NotBlank @Size(max = 128)
        String idempotencyKey,

        @NotBlank @Size(max = 64) @ValidMeterCode
        String meterCode,

        @NotBlank @Size(max = 128)
        String customerRef,

        @NotNull
        Instant occurredAt,

        @NotNull @DecimalMin("0")
        BigDecimal quantity,

        @Nullable
        Map<String, Object> properties
) {

    public Map<String, Object> propertiesOrEmpty() {
        return properties == null ? Map.of() : properties;
    }
}
