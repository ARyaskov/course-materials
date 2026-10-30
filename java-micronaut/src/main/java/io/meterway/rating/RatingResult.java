package io.meterway.rating;

import io.meterway.domain.Money;
import io.micronaut.serde.annotation.Serdeable;

import java.util.List;

@Serdeable
public record RatingResult(List<RatedLine> lines, Money total) {

    public static RatingResult empty(String currency) {
        return new RatingResult(List.of(), Money.zero(currency));
    }
}
