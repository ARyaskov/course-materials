package io.meterway.persistence;

import io.meterway.metering.TimeOrderedUuid;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.IdempotencyRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.persistence.repository.UsageRollup;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Слой данных — единственное место, где ошибка в SQL не ловится компилятором.
 * Каждый {@code @Query}-метод проверяется на реальной базе, и проверяются все поля результата,
 * а не размер списка: неверный псевдоним колонки оставил бы поле null, не изменив размер.
 */
@MicronautTest(transactional = false)
class UsageEventRepositoryTest {

    private static final Instant APRIL = Instant.parse("2026-04-01T00:00:00Z");
    private static final Instant MAY = Instant.parse("2026-05-01T00:00:00Z");
    private static final Instant JUNE = Instant.parse("2026-06-01T00:00:00Z");

    @Inject UsageEventRepository events;
    @Inject IdempotencyRepository idempotency;
    @Inject TenantRepository tenants;
    @Inject CustomerRepository customers;

    private UUID tenantId;
    private CustomerEntity customer;

    @BeforeEach
    void seed() {
        tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "repo-test"));
        customer = customers.save(CustomerEntity.create(tenantId, "ref-" + tenantId, "Repo", "EUR"));
    }

    @Test
    @DisplayName("Проекция агрегации заполняется целиком, включая опциональные поля")
    void rollupMapsAllColumns() {
        Instant moment = APRIL.plusSeconds(36_000);
        events.save(event(moment, "api.requests", BigDecimal.valueOf(600)));
        events.save(event(moment.plusSeconds(60), "api.requests", BigDecimal.valueOf(400)));

        List<UsageRollup> rollups = events.rollup(tenantId, APRIL, MAY);

        assertEquals(1, rollups.size());
        UsageRollup rollup = rollups.getFirst();
        assertEquals(tenantId, rollup.tenantId());
        assertEquals(customer.id(), rollup.customerId());
        assertEquals("api.requests", rollup.meterCode());
        assertEquals(0, rollup.sumValue().compareTo(BigDecimal.valueOf(1000)));
        assertEquals(0, rollup.maxValue().compareTo(BigDecimal.valueOf(600)));
        assertEquals(2L, rollup.eventCount());
        assertEquals(moment.plusSeconds(60), rollup.lastEventAt());
    }

    @Test
    @DisplayName("Захват ключа идемпотентности выигрывает только первый")
    void claimIsWonOnce() {
        String key = "claim-" + UUID.randomUUID();

        assertEquals(1L, idempotency.claim(tenantId, key, "fp", UUID.randomUUID(), APRIL));
        assertEquals(0L, idempotency.claim(tenantId, key, "fp", UUID.randomUUID(), APRIL));
    }

    @Test
    @DisplayName("Событие на границе периода принадлежит только одному периоду")
    void periodBoundaryIsHalfOpen() {
        events.save(event(MAY.minusMillis(1), "api.requests", BigDecimal.ONE));
        events.save(event(MAY, "api.requests", BigDecimal.ONE));

        assertEquals(1L, events.rollup(tenantId, APRIL, MAY).getFirst().eventCount());
        assertEquals(1L, events.rollup(tenantId, MAY, JUNE).getFirst().eventCount());
    }

    @Test
    @DisplayName("UNIQUE_COUNT считает различные значения свойства jsonb")
    void countsDistinctProperty() {
        Instant moment = APRIL.plusSeconds(36_000);
        events.save(event(moment, "seats.active", BigDecimal.ONE, Map.of("user_id", "u-1")));
        events.save(event(moment.plusSeconds(1), "seats.active", BigDecimal.ONE, Map.of("user_id", "u-1")));
        events.save(event(moment.plusSeconds(2), "seats.active", BigDecimal.ONE, Map.of("user_id", "u-2")));

        assertEquals(2L, events.countDistinctProperty(
                tenantId, customer.id(), "seats.active", "user_id", APRIL, MAY));
    }

    private UsageEventEntity event(Instant occurredAt, String meterCode, BigDecimal quantity) {
        return event(occurredAt, meterCode, quantity, Map.of());
    }

    private UsageEventEntity event(Instant occurredAt, String meterCode,
                                   BigDecimal quantity, Map<String, Object> properties) {
        return new UsageEventEntity(TimeOrderedUuid.from(occurredAt.toEpochMilli()),
                tenantId, customer.id(), meterCode, occurredAt, null, quantity, properties, "test");
    }
}
