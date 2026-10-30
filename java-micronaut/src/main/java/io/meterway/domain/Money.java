package io.meterway.domain;

import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Currency;
import java.util.Objects;

/**
 * Денежная величина. Хранится в минорных единицах (копейки, центы) как {@code long},
 * чтобы сложение тысяч строк счёта не зависело от масштаба BigDecimal.
 */
@Serdeable
public record Money(long minorUnits, String currency) implements Comparable<Money> {

    public Money {
        Objects.requireNonNull(currency, "currency");
        if (currency.length() != 3) {
            throw new IllegalArgumentException("Код валюты должен быть трёхбуквенным: " + currency);
        }
    }

    public static Money zero(String currency) {
        return new Money(0L, currency);
    }

    public static Money of(BigDecimal major, String currency) {
        int scale = Currency.getInstance(currency).getDefaultFractionDigits();
        return new Money(major.movePointRight(scale).setScale(0, RoundingMode.HALF_UP).longValueExact(), currency);
    }

    public BigDecimal toMajor() {
        int scale = Currency.getInstance(currency).getDefaultFractionDigits();
        return BigDecimal.valueOf(minorUnits).movePointLeft(scale);
    }

    public Money plus(Money other) {
        requireSameCurrency(other);
        return new Money(Math.addExact(minorUnits, other.minorUnits), currency);
    }

    public Money minus(Money other) {
        requireSameCurrency(other);
        return new Money(Math.subtractExact(minorUnits, other.minorUnits), currency);
    }

    /**
     * Умножение на количество. Округление HALF_UP выполняется один раз, на минорных единицах:
     * это единственное место, где в тарификации теряются доли копейки.
     */
    public Money multiply(BigDecimal quantity) {
        BigDecimal result = BigDecimal.valueOf(minorUnits).multiply(quantity).setScale(0, RoundingMode.HALF_UP);
        return new Money(result.longValueExact(), currency);
    }

    public boolean isZero() {
        return minorUnits == 0L;
    }

    public boolean isNegative() {
        return minorUnits < 0L;
    }

    @Override
    public int compareTo(Money other) {
        requireSameCurrency(other);
        return Long.compare(minorUnits, other.minorUnits);
    }

    private void requireSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException("Разные валюты: %s и %s".formatted(currency, other.currency));
        }
    }

    @Override
    public String toString() {
        return toMajor().toPlainString() + " " + currency;
    }
}
