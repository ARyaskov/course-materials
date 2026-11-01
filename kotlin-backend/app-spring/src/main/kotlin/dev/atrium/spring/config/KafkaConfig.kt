package dev.atrium.spring.config

import dev.atrium.infrastructure.events.BookingEventDto
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer
import org.springframework.kafka.listener.DefaultErrorHandler
import org.springframework.util.backoff.FixedBackOff

/** Poison message: три повтора с секундой, затем в atrium.bookings.DLT и коммит — партиция не блокируется. */
@Configuration(proxyBeanMethods = false)
class KafkaConfig {
    @Bean
    fun errorHandler(template: KafkaTemplate<Any, Any>): DefaultErrorHandler =
        DefaultErrorHandler(DeadLetterPublishingRecoverer(template), FixedBackOff(1_000L, 3L))
}
