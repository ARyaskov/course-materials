package io.meterway.config;

import io.micronaut.context.annotation.ConfigurationInject;
import io.micronaut.context.annotation.ConfigurationProperties;
import io.micronaut.core.bind.annotation.Bindable;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import java.time.Duration;

/**
 * Настройки приёма событий. Неизменяемая конфигурация на record:
 * {@code @ConfigurationInject} говорит Micronaut связать параметры конструктора
 * с ключами {@code meterway.ingest.*}, а {@code @Bindable(defaultValue = ...)} задаёт значения по умолчанию.
 */
@ConfigurationProperties("meterway.ingest")
public record IngestConfiguration(

        @ConfigurationInject
        @Min(1) @Max(10_000)
        @Bindable(defaultValue = "500")
        int maxBatchSize,

        @NotNull
        @Bindable(defaultValue = "48h")
        Duration idempotencyWindow,

        @NotNull
        @Bindable(defaultValue = "72h")
        Duration lateEventTolerance,

        @Bindable(defaultValue = "true")
        boolean publishToKafka,

        @Min(1)
        @Bindable(defaultValue = "16")
        int ingestConcurrency,

        /** Предел числа событий за одно потоковое соединение: поток не имеет естественного конца. */
        @Min(1)
        @Bindable(defaultValue = "1000000")
        int maxStreamEvents,

        /** Пауза между событиями, после которой поток обрывается как забытый. */
        @NotNull
        @Bindable(defaultValue = "60s")
        Duration streamIdleTimeout
) {
}
