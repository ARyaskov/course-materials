package io.meterway.messaging;

import io.micronaut.configuration.kafka.annotation.KafkaClient;
import io.micronaut.configuration.kafka.annotation.KafkaKey;
import io.micronaut.configuration.kafka.annotation.Topic;
import io.micronaut.context.annotation.Requires;
import io.micronaut.messaging.annotation.MessageHeader;

/**
 * Продюсер как интерфейс: реализацию генерирует процессор Micronaut Kafka при компиляции.
 * <p>
 * {@code acks = "all"} выбран сознательно: терять события потребления нельзя, а разница
 * в задержке на фоне записи в PostgreSQL незаметна.
 */
@KafkaClient(
        id = "usage-events",
        acks = KafkaClient.Acknowledge.ALL,
        properties = {
                @io.micronaut.context.annotation.Property(name = "compression.type", value = "lz4"),
                @io.micronaut.context.annotation.Property(name = "linger.ms", value = "20"),
                @io.micronaut.context.annotation.Property(name = "enable.idempotence", value = "true")
        }
)
@Requires(property = "meterway.ingest.publish-to-kafka", value = "true", defaultValue = "true")
public interface UsageEventProducer {

    @Topic("meterway.usage-events")
    void send(@KafkaKey String key,
              @MessageHeader("schema-version") String schemaVersion,
              UsageEventMessage message);

    default void publish(UsageEventMessage message) {
        send(message.partitionKey(), Integer.toString(message.schemaVersion()), message);
    }
}
