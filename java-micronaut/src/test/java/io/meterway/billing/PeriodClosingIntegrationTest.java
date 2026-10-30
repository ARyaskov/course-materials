package io.meterway.billing;

import io.meterway.domain.BillingPeriod;
import io.meterway.metering.AggregationService;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.InvoiceEntity;
import io.meterway.persistence.entity.PlanEntity;
import io.meterway.persistence.entity.PriceComponentEntity;
import io.meterway.persistence.entity.SubscriptionEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.InvoiceLineRepository;
import io.meterway.persistence.repository.InvoiceRepository;
import io.meterway.persistence.repository.PlanRepository;
import io.meterway.persistence.repository.PriceComponentRepository;
import io.meterway.persistence.repository.SubscriptionRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.rating.PriceTier;
import io.meterway.rating.PricingModel;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Полный путь: события -> агрегация -> тарификация -> счёт.
 * <p>
 * Тест закрывает период дважды и проверяет, что второй прогон не создаёт новых счетов:
 * закрытие обязано быть повторяемым, потому что задача висит на каждом поде.
 */
@MicronautTest(transactional = false)
class PeriodClosingIntegrationTest {

    private static final YearMonth MONTH = YearMonth.of(2026, 4);
    private static final BillingPeriod PERIOD = BillingPeriod.ofMonth(MONTH);

    @Inject PeriodClosingService closing;
    @Inject TenantRepository tenants;
    @Inject CustomerRepository customers;
    @Inject PlanRepository plans;
    @Inject PriceComponentRepository priceComponents;
    @Inject SubscriptionRepository subscriptions;
    @Inject UsageEventRepository events;
    @Inject InvoiceRepository invoices;
    @Inject InvoiceLineRepository invoiceLines;
    @Inject UsageAggregateRepository aggregates;
    @Inject AggregationService aggregation;

    @Test
    @DisplayName("Период закрывается один раз: повторный прогон не выставляет второй счёт")
    void closesPeriodIdempotently() {
        UUID tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "Closing test"));

        CustomerEntity customer = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Closing customer", "EUR"));

        PlanEntity plan = plans.save(new PlanEntity(
                UUID.randomUUID(), tenantId, "closing-plan", "Closing plan", "EUR", 9900L, true, null));

        // 0–500 запросов по 2 минорные единицы, дальше по 1: ступенчатая тарификация.
        priceComponents.save(new PriceComponentEntity(
                UUID.randomUUID(), plan.id(), "api.requests", PricingModel.GRADUATED,
                BigDecimal.ZERO,
                List.of(PriceTier.of(0, 500L, 2), PriceTier.of(500, null, 1)),
                0));

        subscriptions.save(new SubscriptionEntity(
                UUID.randomUUID(), tenantId, customer.id(), plan.id(), PERIOD.start(), null, null, null));

        // 1000 запросов внутри периода: 500 * 2 + 500 * 1 = 1500 минорных единиц.
        Instant moment = PERIOD.start().plusSeconds(3600);
        events.save(new UsageEventEntity(UUID.randomUUID(), tenantId, customer.id(), "api.requests",
                moment, null, BigDecimal.valueOf(600), Map.of(), "test"));
        events.save(new UsageEventEntity(UUID.randomUUID(), tenantId, customer.id(), "api.requests",
                moment.plusSeconds(60), null, BigDecimal.valueOf(400), Map.of(), "test"));

        // Пересчёт периода обязан быть повторяемым: он выполняется и по расписанию,
        // и при каждом закрытии. Сложение вместо замены удвоило бы объём в счёте.
        aggregation.recalculate(tenantId, PERIOD);
        aggregation.recalculate(tenantId, PERIOD);

        var afterDoubleRecalculation = aggregates.findByCustomerIdAndMeterCodeAndPeriodStart(
                customer.id(), "api.requests", PERIOD.start()).orElseThrow();
        assertEquals(0, afterDoubleRecalculation.value().compareTo(BigDecimal.valueOf(1000)),
                "полный пересчёт заменяет значение, а не прибавляет его к прежнему");
        assertEquals(2L, afterDoubleRecalculation.eventCount());

        ClosingReport first = closing.close(tenantId, PERIOD);
        assertEquals(1, first.invoicesCreated());
        assertFalse(first.alreadyClosed());

        ClosingReport second = closing.close(tenantId, PERIOD);
        assertTrue(second.alreadyClosed(), "повторное закрытие должно распознаваться");

        List<InvoiceEntity> issued = invoices.findByTenantIdAndPeriodStart(tenantId, PERIOD.start());
        assertEquals(1, issued.size(), "второй счёт за тот же период выставляться не должен");

        InvoiceEntity invoice = issued.getFirst();
        assertEquals(9900L + 1500L, invoice.totalMinor(), "абонентская плата плюс ступенчатая тарификация");

        assertEquals(2, invoiceLines.findByInvoiceIdOrderByPosition(invoice.id()).size());
    }
}
