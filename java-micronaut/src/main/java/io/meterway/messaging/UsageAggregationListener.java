package io.meterway.messaging;

import io.meterway.config.MeterDefinition;
import io.meterway.domain.BillingPeriod;
import io.meterway.metering.MeterCatalog;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.micronaut.configuration.kafka.annotation.KafkaListener;
import io.micronaut.configuration.kafka.annotation.OffsetStrategy;
import io.micronaut.configuration.kafka.annotation.Topic;
import io.micronaut.configuration.kafka.exceptions.KafkaListenerException;
import io.micronaut.configuration.kafka.exceptions.KafkaListenerExceptionHandler;
import io.micronaut.context.annotation.Requires;
import io.micronaut.messaging.Acknowledgement;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * Инкрементальная агрегация принятых событий.
 * <p>
 * Батчевое потребление с ручным коммитом: агрегаты сливаются одной транзакцией,
 * и только после её успеха подтверждается смещение. При падении между записью и коммитом
 * батч придёт повторно — merge идемпотентен по (customer, meter, period) только для MAX и LAST,
 * поэтому для SUM дедупликация обеспечена уникальностью ключа на этапе приёма.
 */
@Singleton
@KafkaListener(
        groupId = "meterway-aggregation",
        offsetStrategy = OffsetStrategy.DISABLED,
        batch = true,
        properties = {
                @io.micronaut.context.annotation.Property(name = "max.poll.records", value = "500")
        }
)
@Requires(property = "meterway.aggregation.enabled", value = "true", defaultValue = "true")
public class UsageAggregationListener implements KafkaListenerExceptionHandler {

    private static final Logger LOG = LoggerFactory.getLogger(UsageAggregationListener.class);

    private final UsageAggregateRepository aggregates;
    private final MeterCatalog catalog;

    public UsageAggregationListener(UsageAggregateRepository aggregates, MeterCatalog catalog) {
        this.aggregates = aggregates;
        this.catalog = catalog;
    }

    @Topic("meterway.usage-events")
    public void onEvents(List<UsageEventMessage> messages, Acknowledgement acknowledgement) {
        try {
            applyBatch(messages);
            acknowledgement.ack();
        } catch (RuntimeException e) {
            LOG.error("Батч из {} событий не применён, смещение не подтверждено", messages.size(), e);
            throw e;
        }
    }

    @Transactional
    protected void applyBatch(List<UsageEventMessage> messages) {
        for (UsageEventMessage message : messages) {
            MeterDefinition definition = catalog.find(message.meterCode()).orElse(null);
            if (definition == null) {
                LOG.warn("Событие {} по неизвестной метрике {} пропущено",
                        message.eventId(), message.meterCode());
                continue;
            }
            BillingPeriod period = BillingPeriod.monthOf(message.occurredAt());
            aggregates.merge(
                    UUID.randomUUID(),
                    message.tenantId(),
                    message.customerId(),
                    message.meterCode(),
                    period.start(),
                    period.end(),
                    definition.getAggregation().name(),
                    message.quantity() == null ? BigDecimal.ZERO : message.quantity(),
                    1L,
                    message.occurredAt());
        }
    }

    @Override
    public void handle(KafkaListenerException exception) {
        LOG.error("Ошибка консьюмера агрегации: {}", exception.getMessage(), exception);
    }
}
