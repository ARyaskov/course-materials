package io.meterway.observability;

import io.meterway.ingest.IngestOutcome;
import io.meterway.ingest.IngestResponse;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.inject.Singleton;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Метрики приёма. Счётчики создаются один раз и переиспользуются:
 * поиск метрики по имени и тегам на каждом событии сам по себе стоит заметно.
 * <p>
 * Тег {@code meter} ограничен каталогом метрик, поэтому кардинальность предсказуема.
 * Тега с идентификатором клиента здесь сознательно нет.
 */
@Singleton
public class IngestMetrics {

    private final MeterRegistry registry;
    private final Counter accepted;
    private final Counter duplicated;
    private final Counter rejected;
    private final Counter idempotencyConflicts;
    private final DistributionSummary batchSize;
    private final Map<String, Counter> quotaBlocks = new ConcurrentHashMap<>();

    public IngestMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.accepted = Counter.builder("meterway.ingest.events")
                .tag("outcome", "accepted")
                .description("События потребления, принятые и записанные")
                .register(registry);
        this.duplicated = Counter.builder("meterway.ingest.events")
                .tag("outcome", "duplicate")
                .register(registry);
        this.rejected = Counter.builder("meterway.ingest.events")
                .tag("outcome", "rejected")
                .register(registry);
        this.idempotencyConflicts = Counter.builder("meterway.ingest.idempotency.conflicts")
                .description("Ключ идемпотентности переиспользован с другим телом")
                .register(registry);
        this.batchSize = DistributionSummary.builder("meterway.ingest.batch.size")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(registry);
    }

    public void recordBatch(IngestResponse response) {
        accepted.increment(response.accepted());
        duplicated.increment(response.duplicated());
        rejected.increment(response.rejected());
        batchSize.record(response.outcomes().size());
    }

    /** Исход одного события потокового приёма: батчевого агрегата здесь нет. */
    public void recordStreamedOutcome(IngestOutcome outcome) {
        switch (outcome) {
            case IngestOutcome.Accepted ignored -> accepted.increment();
            case IngestOutcome.Duplicate ignored -> duplicated.increment();
            default -> rejected.increment();
        }
    }

    public void recordQuotaBlock(String meterCode) {
        quotaBlocks.computeIfAbsent(meterCode, code -> Counter.builder("meterway.quota.blocked")
                .tag("meter", code)
                .description("Отказы из-за исчерпанной квоты")
                .register(registry)).increment();
    }

    public void recordIdempotencyConflict() {
        idempotencyConflicts.increment();
    }
}
