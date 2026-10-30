package io.meterway.rating;

import io.meterway.config.BillingConfiguration;
import io.meterway.domain.Money;
import io.meterway.metering.MeterCatalog;
import io.meterway.persistence.entity.PlanEntity;
import io.meterway.persistence.entity.PriceComponentEntity;
import io.meterway.persistence.entity.UsageAggregateEntity;
import io.meterway.persistence.repository.PlanRepository;
import io.meterway.persistence.repository.PriceComponentRepository;
import io.micronaut.cache.annotation.Cacheable;
import jakarta.inject.Singleton;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Превращает агрегаты потребления в строки счёта по тарифному плану.
 * <p>
 * Движок не ходит в базу за событиями: он работает с уже посчитанными агрегатами.
 * Это разделение позволяет пересчитать период, не перечитывая миллионы строк.
 */
@Singleton
public class RatingEngine {

    private final PlanRepository plans;
    private final PriceComponentRepository components;
    private final TieredPriceCalculator calculator;
    private final MeterCatalog catalog;
    private final BillingConfiguration configuration;

    public RatingEngine(PlanRepository plans,
                        PriceComponentRepository components,
                        TieredPriceCalculator calculator,
                        MeterCatalog catalog,
                        BillingConfiguration configuration) {
        this.plans = plans;
        this.components = components;
        this.calculator = calculator;
        this.catalog = catalog;
        this.configuration = configuration;
    }

    public RatingResult rate(UUID planId, List<UsageAggregateEntity> aggregates) {
        PlanEntity plan = plans.findById(planId)
                .orElseThrow(() -> new IllegalStateException("Тарифный план не найден: " + planId));

        String currency = plan.currency() == null ? configuration.defaultCurrency() : plan.currency();
        Map<String, UsageAggregateEntity> byMeter = aggregates.stream()
                .collect(Collectors.toMap(UsageAggregateEntity::meterCode, Function.identity(), (a, b) -> a));

        List<RatedLine> lines = new ArrayList<>();
        Money total = Money.zero(currency);

        if (plan.fixedFeeMinor() != 0L) {
            Money fixed = new Money(plan.fixedFeeMinor(), currency);
            lines.add(new RatedLine("plan.fixed", "Абонентская плата: " + plan.name(),
                    java.math.BigDecimal.ONE, fixed));
            total = total.plus(fixed);
        }

        for (PriceComponentEntity component : priceComponents(planId)) {
            UsageAggregateEntity aggregate = byMeter.get(component.meterCode());
            if (aggregate == null) {
                continue;
            }
            Money amount = calculator.calculate(
                    component.pricingModel(),
                    component.tiers(),
                    component.includedQuantity(),
                    aggregate.value(),
                    currency);

            if (amount.isZero()) {
                continue;
            }
            String description = catalog.find(component.meterCode())
                    .map(definition -> definition.getDescription().isBlank()
                            ? component.meterCode()
                            : definition.getDescription())
                    .orElse(component.meterCode());

            lines.add(new RatedLine(component.meterCode(), description, aggregate.value(), amount));
            total = total.plus(amount);
        }

        return new RatingResult(List.copyOf(lines), total);
    }

    /** Прайс меняется раз в месяц, а читается на каждом счёте: кэш здесь окупается сразу. */
    @Cacheable(value = "price-components", parameters = "planId")
    protected List<PriceComponentEntity> priceComponents(UUID planId) {
        return components.findByPlanIdOrderByPosition(planId);
    }
}
