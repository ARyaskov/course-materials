package io.meterway.messaging;

import io.micronaut.context.annotation.Requires;
import jakarta.inject.Singleton;

/**
 * Заглушка на случай, когда публикация выключена: сервис приёма не должен знать,
 * подключён ли Kafka. {@code @Requires} гарантирует, что в контейнере окажется ровно один продюсер.
 */
@Singleton
@Requires(property = "meterway.ingest.publish-to-kafka", notEquals = "true")
public class NoopUsageEventProducer implements UsageEventProducer {

    @Override
    public void send(String key, String schemaVersion, UsageEventMessage message) {
        // Публикация отключена.
    }
}
