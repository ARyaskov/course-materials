package io.meterway.ratelimit;

import io.micronaut.context.annotation.EachProperty;
import io.micronaut.context.annotation.Parameter;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import java.time.Duration;

/**
 * Политика лимита.
 * <p>
 * Числа живут в конфигурации, а не в аннотации: лимит — эксплуатационная настройка,
 * и менять её пересборкой неудобно. Аннотация содержит только имя политики.
 */
@EachProperty("meterway.rate-limits")
public class RateLimitPolicy {

    private final String name;

    @Min(1)
    private int limit = 1000;

    @NotNull
    private Duration window = Duration.ofMinutes(1);

    public RateLimitPolicy(@Parameter String name) {
        this.name = name;
    }

    public String getName() {
        return name;
    }

    public int getLimit() {
        return limit;
    }

    public void setLimit(int limit) {
        this.limit = limit;
    }

    public Duration getWindow() {
        return window;
    }

    public void setWindow(Duration window) {
        this.window = window;
    }
}
