package io.meterway.rating;

import jakarta.inject.Singleton;

import java.math.BigDecimal;
import java.util.Comparator;
import java.util.List;

/**
 * Согласованность набора ступеней прайса.
 * <p>
 * JSON-схема описывает форму отдельной ступени, но не может выразить правила о наборе:
 * ступени не должны перекрываться, первая обязана начинаться с нуля, безграничная —
 * быть последней. Ступени попадают в jsonb в том числе миграциями и внешними выгрузками,
 * то есть мимо валидации контроллера, поэтому проверка выполняется при загрузке плана.
 */
@Singleton
public class PriceTierListValidator {

    public void verifyConsistency(List<PriceTier> tiers) {
        if (tiers == null || tiers.isEmpty()) {
            throw new IllegalArgumentException("Прайс без единой ступени");
        }
        List<PriceTier> ordered = tiers.stream()
                .sorted(Comparator.comparing(PriceTier::from))
                .toList();

        if (ordered.getFirst().from().signum() != 0) {
            throw new IllegalArgumentException(
                    "Первая ступень должна начинаться с нуля, начинается с " + ordered.getFirst().from());
        }
        for (int i = 1; i < ordered.size(); i++) {
            PriceTier previous = ordered.get(i - 1);
            PriceTier current = ordered.get(i);
            if (previous.isUnbounded()) {
                throw new IllegalArgumentException("Безграничная ступень должна быть последней");
            }
            BigDecimal boundary = previous.upTo();
            if (boundary.compareTo(current.from()) != 0) {
                throw new IllegalArgumentException(
                        "Разрыв или перекрытие ступеней на границе %s: предыдущая заканчивается на %s"
                                .formatted(current.from(), boundary));
            }
        }
    }
}
