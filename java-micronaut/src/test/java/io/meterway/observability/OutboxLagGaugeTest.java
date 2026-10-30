package io.meterway.observability;

import io.meterway.persistence.entity.OutboxMessageEntity;
import io.meterway.persistence.repository.OutboxRepository;
import io.micrometer.core.instrument.MeterRegistry;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Метрика, на которой построен алерт, обязана работать.
 * <p>
 * Правило {@code meterway_outbox_lag_seconds > 300} из ops/alerts.yml опирается
 * на эти gauge: ошибка в имени или в запросе оставила бы алерт молчащим навсегда.
 */
@MicronautTest(transactional = false)
class OutboxLagGaugeTest {

    @Inject
    OutboxRepository outbox;

    @Inject
    MeterRegistry registry;

    @Test
    @DisplayName("Старое неопубликованное сообщение отражается в отставании")
    void reportsLag() {
        outbox.save(new OutboxMessageEntity(
                UUID.randomUUID(), "invoice", UUID.randomUUID().toString(), "invoice.issued",
                Map.of("tenantId", UUID.randomUUID().toString()),
                Instant.now().minus(Duration.ofMinutes(10)), null));

        var lag = registry.find("meterway.outbox.lag.seconds").gauge();
        var pending = registry.find("meterway.outbox.pending").gauge();

        assertNotNull(lag, "gauge отставания должен быть зарегистрирован");
        assertNotNull(pending, "gauge числа сообщений должен быть зарегистрирован");

        assertTrue(lag.value() >= 600, "отставание не меньше возраста сообщения: " + lag.value());
        assertTrue(pending.value() >= 1, "неопубликованное сообщение должно считаться");
    }
}
