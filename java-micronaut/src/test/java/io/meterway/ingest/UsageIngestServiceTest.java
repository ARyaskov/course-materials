package io.meterway.ingest;

import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;

/**
 * Сервис приёма без HTTP-слоя: проверяется последовательность решений,
 * а не коды ответов. Коды проверяет {@link UsageIngestControllerTest}.
 */
@MicronautTest(transactional = false)
class UsageIngestServiceTest {

    private static final String CUSTOMER_REF = "svc-customer";

    @Inject UsageIngestService service;
    @Inject TenantRepository tenants;
    @Inject CustomerRepository customers;

    private UUID tenantId;

    @BeforeEach
    void seed() {
        tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "service-test"));
        customers.save(CustomerEntity.create(tenantId, CUSTOMER_REF, "Service", "EUR"));
    }

    @Test
    @DisplayName("Первое событие принимается, повтор с тем же телом — дубликат с тем же идентификатором")
    void detectsDuplicate() {
        UsageEventRequest request = event("svc-" + UUID.randomUUID(), BigDecimal.ONE);

        IngestOutcome first = service.ingestOne(tenantId, request);
        IngestOutcome second = service.ingestOne(tenantId, request);

        IngestOutcome.Accepted accepted = assertInstanceOf(IngestOutcome.Accepted.class, first);
        IngestOutcome.Duplicate duplicate = assertInstanceOf(IngestOutcome.Duplicate.class, second);
        assertEquals(accepted.eventId(), duplicate.eventId(),
                "повтор должен вернуть ссылку на то же событие");
    }

    @Test
    @DisplayName("Тот же ключ с другим количеством — конфликт, а не дубликат")
    void detectsKeyReuse() {
        String key = "svc-conflict-" + UUID.randomUUID();
        UsageEventRequest first = event(key, BigDecimal.ONE);
        service.ingestOne(tenantId, first);

        UsageEventRequest changed = new UsageEventRequest(key, first.meterCode(), first.customerRef(),
                first.occurredAt(), BigDecimal.TEN, first.properties());

        assertInstanceOf(IngestOutcome.Conflict.class, service.ingestOne(tenantId, changed));
    }

    @Test
    @DisplayName("Неизвестная метрика отклоняется без обращения к базе")
    void rejectsUnknownMeter() {
        UsageEventRequest request = new UsageEventRequest("svc-meter-" + UUID.randomUUID(),
                "api.nope", CUSTOMER_REF, Instant.now().minusSeconds(60), BigDecimal.ONE, Map.of());

        IngestOutcome.Rejected rejected =
                assertInstanceOf(IngestOutcome.Rejected.class, service.ingestOne(tenantId, request));
        assertEquals("unknown-meter", rejected.code());
    }

    @Test
    @DisplayName("Событие старше окна приёма отклоняется")
    void rejectsTooOldEvent() {
        UsageEventRequest request = new UsageEventRequest("svc-old-" + UUID.randomUUID(),
                "api.requests", CUSTOMER_REF, Instant.now().minus(java.time.Duration.ofDays(30)),
                BigDecimal.ONE, Map.of());

        IngestOutcome.Rejected rejected =
                assertInstanceOf(IngestOutcome.Rejected.class, service.ingestOne(tenantId, request));
        assertEquals("invalid-occurred-at", rejected.code());
    }

    private UsageEventRequest event(String key, BigDecimal quantity) {
        return new UsageEventRequest(key, "api.requests", CUSTOMER_REF,
                Instant.now().minusSeconds(60), quantity, Map.of("endpoint", "/v1/items"));
    }
}
