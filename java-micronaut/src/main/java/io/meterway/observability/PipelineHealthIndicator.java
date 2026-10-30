package io.meterway.observability;

import io.meterway.persistence.repository.OutboxRepository;
import io.micronaut.context.annotation.Requires;
import io.micronaut.health.HealthStatus;
import io.micronaut.management.health.indicator.HealthIndicator;
import io.micronaut.management.health.indicator.HealthResult;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import jakarta.inject.Singleton;
import org.reactivestreams.Publisher;
import reactor.core.publisher.Mono;

import java.time.Clock;
import java.time.Duration;
import java.util.Map;

/**
 * Индикатор отставания конвейера.
 * <p>
 * Здоровье приложения определяет не доступность порта, а способность выполнять работу:
 * непубликуемый outbox означает, что счета выставляются, а уведомления не уходят.
 */
@Singleton
@Requires(beans = OutboxRepository.class)
public class PipelineHealthIndicator implements HealthIndicator {

    private static final String NAME = "meterway-pipeline";

    private final OutboxRepository outbox;
    private final Clock clock;
    private final Duration threshold;

    public PipelineHealthIndicator(OutboxRepository outbox,
                                   Clock clock,
                                   @io.micronaut.context.annotation.Value("${meterway.health.outbox-lag-threshold:5m}")
                                   Duration threshold) {
        this.outbox = outbox;
        this.clock = clock;
        this.threshold = threshold;
    }

    @Override
    @ExecuteOn(TaskExecutors.BLOCKING)
    public Publisher<HealthResult> getResult() {
        return Mono.fromCallable(this::evaluate)
                .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic());
    }

    private HealthResult evaluate() {
        var pending = outbox.lockUnpublished(1);
        if (pending.isEmpty()) {
            return HealthResult.builder(NAME, HealthStatus.UP)
                    .details(Map.of("outboxLagSeconds", 0))
                    .build();
        }
        Duration lag = Duration.between(pending.getFirst().createdAt(), clock.instant());
        HealthStatus status = lag.compareTo(threshold) > 0 ? HealthStatus.DOWN : HealthStatus.UP;
        return HealthResult.builder(NAME, status)
                .details(Map.of(
                        "outboxLagSeconds", lag.toSeconds(),
                        "thresholdSeconds", threshold.toSeconds()))
                .build();
    }
}
