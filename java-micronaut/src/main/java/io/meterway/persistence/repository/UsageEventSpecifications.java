package io.meterway.persistence.repository;

import io.meterway.persistence.entity.UsageEventEntity;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.data.repository.jpa.criteria.PredicateSpecification;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.UUID;

/**
 * Предикаты для динамического фильтра событий.
 * <p>
 * Восемь необязательных параметров дали бы 256 производных методов, а один запрос с
 * {@code (:param is null or column = :param)} планировщик PostgreSQL не смог бы оптимизировать:
 * условие истинно при любом значении параметра, и индекс по этой колонке не используется.
 * Criteria порождает разный SQL под каждый набор условий, и каждый план оптимален.
 * <p>
 * Предикат, вернувший {@code null}, игнорируется — поэтому проверки на отсутствие значения
 * живут внутри самих предикатов, а не в цепочке ветвлений у вызывающего.
 */
public final class UsageEventSpecifications {

    private UsageEventSpecifications() {
    }

    public static PredicateSpecification<UsageEventEntity> tenantIs(UUID tenantId) {
        return (root, builder) -> builder.equal(root.get("tenantId"), tenantId);
    }

    public static PredicateSpecification<UsageEventEntity> customerIs(@Nullable UUID customerId) {
        return (root, builder) -> customerId == null ? null : builder.equal(root.get("customerId"), customerId);
    }

    public static PredicateSpecification<UsageEventEntity> meterIn(@Nullable Collection<String> meterCodes) {
        return (root, builder) -> meterCodes == null || meterCodes.isEmpty()
                ? null
                : root.get("meterCode").in(meterCodes);
    }

    /** Полуинтервал [from, to): именно так определён расчётный период. */
    public static PredicateSpecification<UsageEventEntity> occurredWithin(@Nullable Instant from,
                                                                         @Nullable Instant to) {
        return (root, builder) -> {
            if (from == null && to == null) {
                return null;
            }
            if (from == null) {
                return builder.lessThan(root.get("occurredAt"), to);
            }
            if (to == null) {
                return builder.greaterThanOrEqualTo(root.get("occurredAt"), from);
            }
            return builder.and(
                    builder.greaterThanOrEqualTo(root.get("occurredAt"), from),
                    builder.lessThan(root.get("occurredAt"), to));
        };
    }

    public static PredicateSpecification<UsageEventEntity> quantityAtLeast(@Nullable BigDecimal minimum) {
        return (root, builder) -> minimum == null
                ? null
                : builder.greaterThanOrEqualTo(root.get("quantity"), minimum);
    }

    public static PredicateSpecification<UsageEventEntity> sourceIs(@Nullable String source) {
        return (root, builder) -> source == null ? null : builder.equal(root.get("source"), source);
    }
}
