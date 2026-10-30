package io.meterway.config;

import io.micronaut.context.annotation.ConfigurationProperties;
import io.micronaut.core.bind.annotation.Bindable;
import jakarta.validation.constraints.Pattern;

import java.time.Duration;

/** Настройки расчёта и закрытия периода. */
@ConfigurationProperties("meterway.billing")
public record BillingConfiguration(

        @Pattern(regexp = "[A-Z]{3}")
        @Bindable(defaultValue = "EUR")
        String defaultCurrency,

        /** Сколько ждать опоздавшие события после конца периода, прежде чем закрывать его. */
        @Bindable(defaultValue = "6h")
        Duration closingGracePeriod,

        /** Время удержания распределённой блокировки закрытия периода. */
        @Bindable(defaultValue = "10m")
        Duration closingLockTtl
) {
}
