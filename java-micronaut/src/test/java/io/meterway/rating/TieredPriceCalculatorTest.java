package io.meterway.rating;

import io.meterway.domain.Money;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TieredPriceCalculatorTest {

    private final TieredPriceCalculator calculator = new TieredPriceCalculator();

    private static final List<PriceTier> TIERS = List.of(
            PriceTier.of(0, 500L, 2),
            PriceTier.of(500, null, 1));

    @Test
    @DisplayName("GRADUATED: каждая ступень тарифицируется по своей цене")
    void graduatedSplitsAcrossTiers() {
        Money amount = calculator.calculate(
                PricingModel.GRADUATED, TIERS, BigDecimal.ZERO, BigDecimal.valueOf(1000), "EUR");

        assertEquals(500 * 2 + 500 * 1, amount.minorUnits());
    }

    @Test
    @DisplayName("VOLUME: весь объём идёт по цене попавшей ступени")
    void volumeUsesSingleTier() {
        Money amount = calculator.calculate(
                PricingModel.VOLUME, TIERS, BigDecimal.ZERO, BigDecimal.valueOf(1000), "EUR");

        assertEquals(1000 * 1, amount.minorUnits());
    }

    @Test
    @DisplayName("Объём ровно на границе ступени попадает в следующую и не тарифицируется дважды")
    void boundaryBelongsToNextTier() {
        Money graduated = calculator.calculate(
                PricingModel.GRADUATED, TIERS, BigDecimal.ZERO, BigDecimal.valueOf(500), "EUR");
        assertEquals(500 * 2, graduated.minorUnits());

        Money volume = calculator.calculate(
                PricingModel.VOLUME, TIERS, BigDecimal.ZERO, BigDecimal.valueOf(500), "EUR");
        assertEquals(500 * 1, volume.minorUnits());
    }

    @Test
    @DisplayName("Включённый объём вычитается до тарификации и не уходит в минус")
    void includedQuantityIsSubtracted() {
        Money amount = calculator.calculate(
                PricingModel.GRADUATED, TIERS, BigDecimal.valueOf(600), BigDecimal.valueOf(1000), "EUR");
        assertEquals(400 * 2, amount.minorUnits());

        Money free = calculator.calculate(
                PricingModel.GRADUATED, TIERS, BigDecimal.valueOf(2000), BigDecimal.valueOf(1000), "EUR");
        assertEquals(0L, free.minorUnits());
    }

    @Test
    @DisplayName("PACKAGE: начатый пакет оплачивается целиком")
    void packageRoundsUp() {
        List<PriceTier> packages = List.of(
                new PriceTier(BigDecimal.ZERO, null, 500L, 0L, BigDecimal.valueOf(1000)));

        Money amount = calculator.calculate(
                PricingModel.PACKAGE, packages, BigDecimal.ZERO, BigDecimal.valueOf(1001), "EUR");
        assertEquals(2 * 500L, amount.minorUnits());
    }
}
