package io.meterway.messaging;

import io.meterway.persistence.entity.OutboxMessageEntity;
import io.meterway.persistence.repository.OutboxRepository;
import io.meterway.webhook.WebhookDispatcher;
import io.micronaut.context.annotation.Requires;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.scheduling.annotation.Scheduled;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

/**
 * Разбор transactional outbox.
 * <p>
 * {@code for update skip locked} в репозитории позволяет нескольким подам разбирать очередь
 * параллельно без выборов лидера: каждый забирает свою порцию строк и не ждёт чужие.
 */
@Singleton
@Requires(property = "meterway.outbox.enabled", value = "true", defaultValue = "true")
public class OutboxPublisher {

    private static final Logger LOG = LoggerFactory.getLogger(OutboxPublisher.class);

    private final OutboxRepository outbox;
    private final WebhookDispatcher dispatcher;
    private final Clock clock;

    public OutboxPublisher(OutboxRepository outbox, WebhookDispatcher dispatcher, Clock clock) {
        this.outbox = outbox;
        this.dispatcher = dispatcher;
        this.clock = clock;
    }

    @Scheduled(fixedDelay = "${meterway.outbox.poll-interval:5s}")
    @ExecuteOn(TaskExecutors.BLOCKING)
    @Transactional
    public void drain() {
        List<OutboxMessageEntity> batch = outbox.lockUnpublished(200);
        if (batch.isEmpty()) {
            return;
        }
        UUID[] published = new UUID[batch.size()];
        int index = 0;
        for (OutboxMessageEntity message : batch) {
            dispatcher.enqueue(message);
            published[index++] = message.id();
        }
        outbox.markPublished(published, clock.instant());
        LOG.debug("Из outbox отправлено сообщений: {}", published.length);
    }
}
