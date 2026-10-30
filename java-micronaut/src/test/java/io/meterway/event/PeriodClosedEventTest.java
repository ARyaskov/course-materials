package io.meterway.event;

import io.meterway.billing.PeriodClosingService;
import io.meterway.domain.BillingPeriod;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.PlanEntity;
import io.meterway.persistence.entity.PriceComponentEntity;
import io.meterway.persistence.entity.SubscriptionEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.PlanRepository;
import io.meterway.persistence.repository.PriceComponentRepository;
import io.meterway.persistence.repository.SubscriptionRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.rating.PriceTier;
import io.meterway.rating.PricingModel;
import io.micronaut.context.annotation.Requires;
import io.micronaut.runtime.event.annotation.EventListener;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Закрытие периода публикует доменное событие, а слушатель его получает.
 * <p>
 * Зонд ограничен окружением: слушатель без {@code @Requires} попал бы во все тестовые
 * контексты и собирал бы события соседних тестов.
 */
@MicronautTest(transactional = false, environments = "event-test")
class PeriodClosedEventTest {

    private static final YearMonth MONTH = YearMonth.of(2026, 5);
    private static final BillingPeriod PERIOD = BillingPeriod.ofMonth(MONTH);

    @Singleton
    @Requires(env = "event-test")
    static class Probe {

        static final List<PeriodClosedEvent> received = new CopyOnWriteArrayList<>();

        @EventListener
        void capture(PeriodClosedEvent event) {
            received.add(event);
        }
    }

    @Inject PeriodClosingService closing;
    @Inject TenantRepository tenants;
    @Inject CustomerRepository customers;
    @Inject PlanRepository plans;
    @Inject PriceComponentRepository priceComponents;
    @Inject SubscriptionRepository subscriptions;
    @Inject UsageEventRepository events;

    @Test
    @DisplayName("Закрытие периода публикует событие после коммита")
    void publishesAfterCommit() {
        Probe.received.clear();
        UUID tenantId = seed();

        closing.close(tenantId, PERIOD);

        List<PeriodClosedEvent> ours = Probe.received.stream()
                .filter(event -> event.report().tenantId().equals(tenantId))
                .toList();

        assertEquals(1, ours.size(), "событие публикуется ровно один раз");
        assertEquals(PERIOD, ours.getFirst().report().period());
        assertEquals(1, ours.getFirst().report().invoicesCreated());
    }

    @Test
    @DisplayName("Повторное закрытие события не публикует: закрывать нечего")
    void doesNotPublishOnAlreadyClosed() {
        Probe.received.clear();
        UUID tenantId = seed();

        closing.close(tenantId, PERIOD);
        closing.close(tenantId, PERIOD);

        long ours = Probe.received.stream()
                .filter(event -> event.report().tenantId().equals(tenantId))
                .count();

        assertEquals(1, ours, "второе закрытие возвращает alreadyClosed и события не даёт");
        assertTrue(Probe.received.stream().noneMatch(event -> event.report().alreadyClosed()));
    }

    private UUID seed() {
        UUID tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "Event tenant"));

        CustomerEntity customer = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Event customer", "EUR"));

        PlanEntity plan = plans.save(new PlanEntity(
                UUID.randomUUID(), tenantId, "plan-" + tenantId, "Event plan", "EUR", 1000L, true, null));

        priceComponents.save(new PriceComponentEntity(
                UUID.randomUUID(), plan.id(), "api.requests", PricingModel.GRADUATED,
                BigDecimal.ZERO, List.of(PriceTier.of(0, null, 1)), 0));

        subscriptions.save(new SubscriptionEntity(
                UUID.randomUUID(), tenantId, customer.id(), plan.id(), PERIOD.start(), null, null, null));

        events.save(new UsageEventEntity(UUID.randomUUID(), tenantId, customer.id(), "api.requests",
                PERIOD.start().plusSeconds(3600), null, BigDecimal.valueOf(10), Map.of(), "test"));

        return tenantId;
    }
}
