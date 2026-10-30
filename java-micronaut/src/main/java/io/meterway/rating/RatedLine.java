package io.meterway.rating;

import io.meterway.domain.Money;
import io.micronaut.serde.annotation.Serdeable;

import java.math.BigDecimal;

/** Одна строка расчёта: сколько потребили по метрике и во что это обошлось. */
@Serdeable
public record RatedLine(String meterCode, String description, BigDecimal quantity, Money amount) {
}
