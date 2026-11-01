package dev.atrium.spring.health

import org.springframework.boot.health.contributor.Health
import org.springframework.boot.health.contributor.HealthIndicator
import org.springframework.kafka.config.KafkaListenerEndpointRegistry
import org.springframework.stereotype.Component

/** Дешёвый индикатор для группы readiness: читает состояние контейнеров, в Kafka не ходит (урок 15.2). */
@Component("kafkaConsumer")
class KafkaConsumerHealthIndicator(private val registry: KafkaListenerEndpointRegistry) : HealthIndicator {
    override fun health(): Health {
        val containers = registry.listenerContainers
        val stopped = containers.filterNot { it.isRunning }.map { it.listenerId }
        return if (stopped.isEmpty()) Health.up().withDetail("listeners", containers.size).build()
        else Health.down().withDetail("stopped", stopped).build()
    }
}
