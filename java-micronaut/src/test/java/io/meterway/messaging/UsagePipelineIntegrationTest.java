package io.meterway.messaging;

import io.meterway.domain.BillingPeriod;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.entity.UsageAggregateEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.micronaut.context.annotation.Property;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.YearMonth;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Полный путь через Kafka: продюсер -> топик -> батчевый консьюмер -> агрегаты.
 * <p>
 * Контейнер Kafka поднимает Micronaut Test Resources: в тесте нет ни строки про брокер,
 * адрес подставляется автоматически. Тест намеренно один на весь конвейер — остальные
 * проверки логики делаются прямым вызовом методов, без брокера.
 */
@MicronautTest(transactional = false)
@Property(name = "meterway.ingest.publish-to-kafka", value = "true")
@Property(name = "meterway.aggregation.enabled", value = "true")
class UsagePipelineIntegrationTest {

    private static final YearMonth MONTH = YearMonth.of(2026, 6);
    private static final BillingPeriod PERIOD = BillingPeriod.ofMonth(MONTH);
    private static final String METER = "api.requests";

    @Inject
    UsageEventProducer producer;

    @Inject
    TenantRepository tenants;

    @Inject
    CustomerRepository customers;

    @Inject
    UsageAggregateRepository aggregates;

    @Test
    @DisplayName("Событие проходит топик и попадает в агрегат")
    void eventReachesAggregate() throws Exception {
        UUID tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "Pipeline tenant"));
        UUID customerId = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Pipeline customer", "EUR")).id();

        Instant moment = PERIOD.start().plusSeconds(3600);
        producer.publish(new UsageEventMessage(
                UUID.randomUUID(), tenantId, customerId, METER, moment,
                BigDecimal.valueOf(7), Map.of(), UsageEventMessage.CURRENT_SCHEMA_VERSION));
        producer.publish(new UsageEventMessage(
                UUID.randomUUID(), tenantId, customerId, METER, moment.plusSeconds(60),
                BigDecimal.valueOf(5), Map.of(), UsageEventMessage.CURRENT_SCHEMA_VERSION));

        UsageAggregateEntity aggregate = awaitAggregate(customerId, Duration.ofSeconds(60));

        assertEquals(0, aggregate.value().compareTo(BigDecimal.valueOf(12)),
                "инкрементальная агрегация складывает количества по ключу");
        assertEquals(2L, aggregate.eventCount());
    }

    /**
     * Ожидание с опросом, а не фиксированная пауза: доставка через брокер асинхронна,
     * и Thread.sleep дал бы либо медленный, либо нестабильный тест.
     */
    private UsageAggregateEntity awaitAggregate(UUID customerId, Duration timeout) throws Exception {
        Instant deadline = Instant.now().plus(timeout);
        while (Instant.now().isBefore(deadline)) {
            Optional<UsageAggregateEntity> found = aggregates
                    .findByCustomerIdAndMeterCodeAndPeriodStart(customerId, METER, PERIOD.start());
            if (found.isPresent() && found.get().eventCount() >= 2L) {
                return found.get();
            }
            Thread.sleep(200);
        }
        throw new AssertionError("Агрегат не появился за " + timeout);
    }
}
