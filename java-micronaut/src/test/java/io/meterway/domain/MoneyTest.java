package io.meterway.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MoneyTest {

    @Test
    @DisplayName("Сумма из мажорных единиц переводится в минорные без потери копеек")
    void convertsMajorToMinor() {
        assertEquals(9999L, Money.of(new BigDecimal("99.99"), "EUR").minorUnits());
        assertEquals(new BigDecimal("99.99"), Money.of(new BigDecimal("99.99"), "EUR").toMajor());
    }

    @Test
    @DisplayName("Округление происходит один раз, на минорных единицах")
    void roundsOnceOnMultiply() {
        Money unitPrice = new Money(2L, "EUR");
        assertEquals(3L, unitPrice.multiply(new BigDecimal("1.5")).minorUnits());
        assertEquals(2L, unitPrice.multiply(new BigDecimal("1.2")).minorUnits());
    }

    @Test
    @DisplayName("Сложение сумм в разных валютах запрещено")
    void rejectsMixedCurrencies() {
        assertThrows(IllegalArgumentException.class,
                () -> Money.zero("EUR").plus(Money.zero("USD")));
    }

    @Test
    @DisplayName("Тысяча строк счёта складывается без накопления погрешности")
    void sumsWithoutDrift() {
        Money total = Money.zero("EUR");
        for (int i = 0; i < 1000; i++) {
            total = total.plus(new Money(1L, "EUR"));
        }
        assertEquals(1000L, total.minorUnits());
        assertEquals(new BigDecimal("10.00"), total.toMajor());
    }

    @Test
    void detectsSign() {
        assertTrue(Money.zero("EUR").isZero());
        assertTrue(new Money(-1L, "EUR").isNegative());
    }
}
