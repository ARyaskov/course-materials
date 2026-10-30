package io.meterway.realtime;

import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Serdeable
public record UsageUpdate(
        UUID customerId,
        String meterCode,
        BigDecimal value,
        long eventCount,
        Instant at
) {
}
