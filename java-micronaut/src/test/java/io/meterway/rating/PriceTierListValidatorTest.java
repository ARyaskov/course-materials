package io.meterway.rating;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Правила о наборе ступеней, которые невозможно выразить JSON-схемой:
 * она описывает форму отдельной ступени, но не взаимный порядок и не покрытие диапазона.
 */
class PriceTierListValidatorTest {

    private final PriceTierListValidator validator = new PriceTierListValidator();

    @Test
    @DisplayName("Корректный набор ступеней проходит проверку")
    void acceptsWellFormedTiers() {
        assertDoesNotThrow(() -> validator.verifyConsistency(
                List.of(PriceTier.of(0, 500L, 2), PriceTier.of(500, null, 1))));
    }

    @Test
    @DisplayName("Первая ступень обязана начинаться с нуля")
    void rejectsGapAtStart() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> validator.verifyConsistency(List.of(PriceTier.of(100, null, 1))));

        assertTrue(error.getMessage().contains("с нуля"));
    }

    @Test
    @DisplayName("Разрыв между ступенями не допускается")
    void rejectsGapBetweenTiers() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> validator.verifyConsistency(
                        List.of(PriceTier.of(0, 500L, 2), PriceTier.of(700, null, 1))));

        assertTrue(error.getMessage().contains("Разрыв"));
    }

    @Test
    @DisplayName("Безграничная ступень должна быть последней")
    void rejectsUnboundedInTheMiddle() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                () -> validator.verifyConsistency(
                        List.of(PriceTier.of(0, null, 2),
                                new PriceTier(BigDecimal.valueOf(500), null, 1L, 0L, null))));

        assertTrue(error.getMessage().contains("последней"));
    }

    @Test
    @DisplayName("Пустой прайс — ошибка конфигурации плана")
    void rejectsEmptyTiers() {
        assertThrows(IllegalArgumentException.class, () -> validator.verifyConsistency(List.of()));
    }
}
