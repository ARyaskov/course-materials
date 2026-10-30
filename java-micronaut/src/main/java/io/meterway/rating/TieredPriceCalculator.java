package io.meterway.rating;

import io.meterway.domain.Money;
import jakarta.inject.Singleton;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

/**
 * Расчёт стоимости объёма по ступеням.
 * <p>
 * Главная ловушка ступенчатой тарификации — границы. Ступень задана полуинтервалом
 * {@code [from, upTo)}, поэтому объём ровно на границе попадает в следующую ступень
 * и не тарифицируется дважды.
 */
@Singleton
public class TieredPriceCalculator {

    public Money calculate(PricingModel model, List<PriceTier> tiers,
                           BigDecimal includedQuantity, BigDecimal quantity, String currency) {

        BigDecimal billable = quantity.subtract(includedQuantity).max(BigDecimal.ZERO);
        if (billable.signum() == 0 || tiers.isEmpty()) {
            return Money.zero(currency);
        }

        List<PriceTier> ordered = tiers.stream()
                .sorted(java.util.Comparator.comparing(PriceTier::from))
                .toList();

        return switch (model) {
            case FLAT -> flat(ordered.getFirst(), billable, currency);
            case GRADUATED -> graduated(ordered, billable, currency);
            case VOLUME -> volume(ordered, billable, currency);
            case PACKAGE -> packaged(ordered, billable, currency);
        };
    }

    private Money flat(PriceTier tier, BigDecimal quantity, String currency) {
        return new Money(tier.unitPriceMinor(), currency)
                .multiply(quantity)
                .plus(new Money(tier.flatFeeMinor(), currency));
    }

    /** Каждая ступень тарифицируется по своей цене за попавший в неё объём. */
    private Money graduated(List<PriceTier> tiers, BigDecimal quantity, String currency) {
        Money total = Money.zero(currency);
        BigDecimal remaining = quantity;

        for (PriceTier tier : tiers) {
            if (remaining.signum() <= 0) {
                break;
            }
            BigDecimal tierCapacity = tier.isUnbounded()
                    ? remaining
                    : tier.upTo().subtract(tier.from());
            BigDecimal inThisTier = remaining.min(tierCapacity);

            total = total
                    .plus(new Money(tier.unitPriceMinor(), currency).multiply(inThisTier))
                    .plus(new Money(tier.flatFeeMinor(), currency));

            remaining = remaining.subtract(inThisTier);
        }
        return total;
    }

    /** Весь объём тарифицируется по цене той ступени, в которую он попал. */
    private Money volume(List<PriceTier> tiers, BigDecimal quantity, String currency) {
        PriceTier matched = tiers.getLast();
        for (PriceTier tier : tiers) {
            boolean fits = quantity.compareTo(tier.from()) >= 0
                    && (tier.isUnbounded() || quantity.compareTo(tier.upTo()) < 0);
            if (fits) {
                matched = tier;
                break;
            }
        }
        return new Money(matched.unitPriceMinor(), currency)
                .multiply(quantity)
                .plus(new Money(matched.flatFeeMinor(), currency));
    }

    /** Плата за начатый пакет: 1001 запрос при пакете в 1000 стоит как два пакета. */
    private Money packaged(List<PriceTier> tiers, BigDecimal quantity, String currency) {
        PriceTier tier = tiers.getFirst();
        BigDecimal packageSize = tier.packageSize() == null ? BigDecimal.ONE : tier.packageSize();
        BigDecimal packages = quantity.divide(packageSize, 0, RoundingMode.CEILING);
        return new Money(tier.unitPriceMinor(), currency).multiply(packages);
    }
}
