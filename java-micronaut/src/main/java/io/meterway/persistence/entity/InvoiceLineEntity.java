package io.meterway.persistence.entity;

import io.micronaut.data.annotation.Id;
import io.micronaut.data.annotation.MappedEntity;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.util.UUID;

@Serdeable
@MappedEntity("invoice_lines")
public record InvoiceLineEntity(
        @Id UUID id,
        UUID invoiceId,
        String meterCode,
        String description,
        BigDecimal quantity,
        long amountMinor,
        int position
) {
}
