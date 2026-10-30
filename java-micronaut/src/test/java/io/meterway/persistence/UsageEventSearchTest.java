package io.meterway.persistence;

import io.meterway.billing.UsageEventQueryService;
import io.meterway.metering.TimeOrderedUuid;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.persistence.repository.UsageEventFilter;
import io.meterway.persistence.repository.UsageEventRepository;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Динамический фильтр событий.
 * <p>
 * Первый тест важнее остальных: он фиксирует, что фильтр тенанта нельзя обойти пустым
 * набором условий. Это структурное свойство, а не поведение конкретного запроса.
 */
@MicronautTest(transactional = false)
class UsageEventSearchTest {

    private static final Instant APRIL = Instant.parse("2026-04-01T00:00:00Z");
    private static final Instant MAY = Instant.parse("2026-05-01T00:00:00Z");

    @Inject UsageEventQueryService search;
    @Inject UsageEventRepository events;
    @Inject TenantRepository tenants;
    @Inject CustomerRepository customers;

    @Test
    @DisplayName("Фильтр без условий возвращает только события своего тенанта")
    void alwaysFiltersByTenant() {
        UUID first = seedTenant(3);
        UUID second = seedTenant(5);

        Page<UsageEventEntity> page = search.search(first, UsageEventFilter.empty(), Pageable.from(0, 100));

        assertEquals(3, page.getTotalSize());
        assertTrue(page.getContent().stream().allMatch(event -> event.tenantId().equals(first)));
        assertEquals(5, search.count(second, UsageEventFilter.empty()));
    }

    @Test
    @DisplayName("Условия комбинируются по конъюнкции")
    void combinesConditions() {
        UUID tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "search-combined"));
        CustomerEntity customer = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Search", "EUR"));

        events.save(event(tenantId, customer.id(), APRIL.plusSeconds(10), "api.requests", BigDecimal.valueOf(50)));
        events.save(event(tenantId, customer.id(), APRIL.plusSeconds(20), "api.requests", BigDecimal.valueOf(500)));
        events.save(event(tenantId, customer.id(), APRIL.plusSeconds(30), "egress.gb", BigDecimal.valueOf(500)));

        Page<UsageEventEntity> page = search.search(tenantId,
                new UsageEventFilter(customer.id(), List.of("api.requests"), APRIL, MAY,
                        BigDecimal.valueOf(100), null),
                Pageable.from(0, 100));

        assertEquals(1, page.getTotalSize());
        assertEquals("api.requests", page.getContent().getFirst().meterCode());
    }

    private UUID seedTenant(int eventCount) {
        UUID tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "search-" + tenantId));
        CustomerEntity customer = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Search", "EUR"));
        for (int i = 0; i < eventCount; i++) {
            events.save(event(tenantId, customer.id(), APRIL.plusSeconds(i),
                    "api.requests", BigDecimal.ONE));
        }
        return tenantId;
    }

    private UsageEventEntity event(UUID tenantId, UUID customerId, Instant occurredAt,
                                   String meterCode, BigDecimal quantity) {
        return new UsageEventEntity(TimeOrderedUuid.from(occurredAt.toEpochMilli()),
                tenantId, customerId, meterCode, occurredAt, null, quantity, Map.of(), "test");
    }
}
