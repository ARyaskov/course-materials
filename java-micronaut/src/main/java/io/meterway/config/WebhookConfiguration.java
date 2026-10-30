package io.meterway.config;

import io.micronaut.context.annotation.ConfigurationProperties;
import io.micronaut.core.bind.annotation.Bindable;

import java.time.Duration;

/** Настройки исходящих уведомлений. */
@ConfigurationProperties("meterway.webhooks")
public record WebhookConfiguration(

        @Bindable(defaultValue = "true")
        boolean enabled,

        @Bindable(defaultValue = "5")
        int maxAttempts,

        @Bindable(defaultValue = "10s")
        Duration initialBackoff,

        @Bindable(defaultValue = "2.0")
        double backoffMultiplier,

        @Bindable(defaultValue = "1h")
        Duration maxBackoff,

        @Bindable(defaultValue = "Meterway-Signature")
        String signatureHeader
) {
}
