package io.meterway.config;

import io.meterway.domain.AggregationType;
import io.meterway.domain.QuantityUnit;
import io.micronaut.context.annotation.EachProperty;
import io.micronaut.context.annotation.Parameter;
import io.micronaut.core.annotation.Nullable;
import jakarta.annotation.PostConstruct;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * Определение метрики, поднятое из конфигурации.
 * <p>
 * Одна секция {@code meterway.meters.*} — один бин {@code MeterDefinition}, поэтому реестру
 * достаточно внедрить {@code List<MeterDefinition>}, чтобы получить весь каталог.
 * <p>
 * Именем секции Micronaut считает <b>ровно один</b> сегмент после префикса. Код метрики содержит
 * точку ({@code api.requests}), а точка в ключе означает вложенность, поэтому имя секции пишется
 * через дефис, а настоящий код задаётся свойством {@code code}.
 */
@EachProperty("meterway.meters")
public class MeterDefinition {

    private final String name;

    @Nullable
    private String code;

    @NotNull
    private AggregationType aggregation = AggregationType.SUM;

    @NotNull
    private QuantityUnit unit = QuantityUnit.UNIT;

    @Nullable
    @Pattern(regexp = "[a-z][a-z0-9_]*", message = "Свойство для UNIQUE_COUNT должно быть в snake_case")
    private String uniqueBy;

    private boolean quotaEnforced = false;

    private String description = "";

    public MeterDefinition(@Parameter String name) {
        this.name = name;
    }

    @PostConstruct
    void validate() {
        if (aggregation == AggregationType.UNIQUE_COUNT && (uniqueBy == null || uniqueBy.isBlank())) {
            throw new IllegalStateException(
                    "Метрика %s объявлена UNIQUE_COUNT, но meterway.meters.%s.unique-by не задан"
                            .formatted(getCode(), name));
        }
        if (aggregation != AggregationType.UNIQUE_COUNT && uniqueBy != null) {
            throw new IllegalStateException(
                    "Метрика %s не является UNIQUE_COUNT, но meterway.meters.%s.unique-by задан"
                            .formatted(getCode(), name));
        }
    }

    /** Имя секции конфигурации. Оно же — квалификатор бина. */
    public String getName() {
        return name;
    }

    /** Код метрики: {@code api.requests}, {@code storage.gb_hours}. По умолчанию совпадает с именем секции. */
    public String getCode() {
        return code == null ? name : code;
    }

    public void setCode(@Nullable String code) {
        this.code = code;
    }

    public AggregationType getAggregation() {
        return aggregation;
    }

    public void setAggregation(AggregationType aggregation) {
        this.aggregation = aggregation;
    }

    public QuantityUnit getUnit() {
        return unit;
    }

    public void setUnit(QuantityUnit unit) {
        this.unit = unit;
    }

    @Nullable
    public String getUniqueBy() {
        return uniqueBy;
    }

    public void setUniqueBy(@Nullable String uniqueBy) {
        this.uniqueBy = uniqueBy;
    }

    public boolean isQuotaEnforced() {
        return quotaEnforced;
    }

    public void setQuotaEnforced(boolean quotaEnforced) {
        this.quotaEnforced = quotaEnforced;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
