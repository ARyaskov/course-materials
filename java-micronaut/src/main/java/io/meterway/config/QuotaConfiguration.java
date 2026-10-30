package io.meterway.config;

import io.micronaut.context.annotation.ConfigurationProperties;
import io.micronaut.core.bind.annotation.Bindable;

import java.time.Duration;

/** Настройки подсистемы квот: где считаем и как долго живут счётчики в Redis. */
@ConfigurationProperties("meterway.quota")
public record QuotaConfiguration(

        @Bindable(defaultValue = "true")
        boolean enabled,

        @Bindable(defaultValue = "meterway:quota")
        String keyPrefix,

        @Bindable(defaultValue = "35d")
        Duration counterTtl,

        /** Разрешать приём событий, если Redis недоступен. Fail-open против fail-closed. */
        @Bindable(defaultValue = "true")
        boolean failOpen
) {
}
