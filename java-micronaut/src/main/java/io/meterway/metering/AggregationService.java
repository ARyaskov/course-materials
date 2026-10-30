package io.meterway.metering;

import io.meterway.config.MeterDefinition;
import io.meterway.domain.AggregationType;
import io.meterway.domain.BillingPeriod;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.persistence.repository.UsageRollup;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Пересчёт агрегатов за период.
 * <p>
 * Инкрементальное обновление делает {@code merge} в репозитории: арифметика выполняется
 * на стороне PostgreSQL, поэтому два консьюмера, попавших на один агрегат,
 * не затирают результат друг друга.
 */
@Singleton
public class AggregationService {

    private static final Logger LOG = LoggerFactory.getLogger(AggregationService.class);

    private final UsageEventRepository events;
    private final UsageAggregateRepository aggregates;
    private final MeterCatalog catalog;

    public AggregationService(UsageEventRepository events,
                              UsageAggregateRepository aggregates,
                              MeterCatalog catalog) {
        this.events = events;
        this.aggregates = aggregates;
        this.catalog = catalog;
    }

    /**
     * Полный пересчёт периода из сырых событий. Используется при закрытии периода
     * и при реплее: инкрементальные обновления могли разойтись с истиной из-за опоздавших событий.
     * <p>
     * Здесь вызывается {@code replace}, а не {@code merge}: пересчитанное значение уже содержит
     * весь объём периода, и сложение его с инкрементальным агрегатом удвоило бы счёт.
     */
    @Transactional
    public int recalculate(UUID tenantId, BillingPeriod period) {
        int updated = 0;
        for (UsageRollup rollup : events.rollup(tenantId, period.start(), period.end())) {
            MeterDefinition definition = catalog.find(rollup.meterCode()).orElse(null);
            if (definition == null) {
                LOG.warn("События по неизвестной метрике {} пропущены при пересчёте", rollup.meterCode());
                continue;
            }
            BigDecimal value = valueFor(definition, rollup, tenantId, period);
            aggregates.replace(
                    UUID.randomUUID(),
                    tenantId,
                    rollup.customerId(),
                    rollup.meterCode(),
                    period.start(),
                    period.end(),
                    definition.getAggregation().name(),
                    value,
                    rollup.eventCount(),
                    rollup.lastEventAt());
            updated++;
        }
        LOG.info("Период {} для тенанта {}: обновлено агрегатов {}", period.label(), tenantId, updated);
        return updated;
    }

    private BigDecimal valueFor(MeterDefinition definition, UsageRollup rollup,
                                UUID tenantId, BillingPeriod period) {
        AggregationType type = definition.getAggregation();
        return switch (type) {
            case SUM -> rollup.sumValue() == null ? BigDecimal.ZERO : rollup.sumValue();
            case MAX -> rollup.maxValue() == null ? BigDecimal.ZERO : rollup.maxValue();
            case LAST -> rollup.maxValue() == null ? BigDecimal.ZERO : rollup.maxValue();
            case UNIQUE_COUNT -> {
                String property = definition.getUniqueBy();
                if (property == null) {
                    throw new IllegalStateException(
                            "Метрика %s объявлена UNIQUE_COUNT, но unique-by не задан".formatted(definition.getCode()));
                }
                yield BigDecimal.valueOf(events.countDistinctProperty(
                        tenantId, rollup.customerId(), definition.getCode(),
                        property, period.start(), period.end()));
            }
        };
    }
}
