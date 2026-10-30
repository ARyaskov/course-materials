package io.meterway.billing;

import io.meterway.domain.BillingPeriod;
import io.micronaut.serde.annotation.Serdeable;

import java.util.UUID;

@Serdeable
public record ClosingReport(UUID tenantId, BillingPeriod period, int invoicesCreated,
                            int invoicesSkipped, boolean alreadyClosed) {
}
