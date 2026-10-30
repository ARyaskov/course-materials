package beacon.metrics;

import beacon.domain.ProbeOutcome;
import java.util.EnumMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import javax.inject.Inject;
import javax.inject.Singleton;

/**
 * Минимальный реестр метрик без внешних зависимостей.
 *
 * <p>Показывает подход: счётчики и гистограммы живут в одном синглтоне, фильтр и
 * планировщик только пишут в них, а {@code /metrics} рендерит текстовый формат
 * Prometheus. Для боевой системы сюда обычно ставят Micrometer, но принцип тот же —
 * реестр инжектится как обычная зависимость Play.
 */
@Singleton
public class BeaconMetrics {

    private static final long[] BUCKETS_MS = {5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000};

    private final Map<String, AtomicLong> httpRequests = new ConcurrentHashMap<>();
    private final AtomicLong[] httpDurations = newBuckets();
    private final AtomicLong httpDurationSum = new AtomicLong();
    private final AtomicLong httpDurationCount = new AtomicLong();

    private final Map<ProbeOutcome, AtomicLong> probes = new EnumMap<>(ProbeOutcome.class);
    private final AtomicLong[] probeDurations = newBuckets();
    private final AtomicLong probeDurationSum = new AtomicLong();
    private final AtomicLong probeDurationCount = new AtomicLong();

    private final AtomicLong skippedTicks = new AtomicLong();
    private final AtomicLong lastBatchSize = new AtomicLong();
    private final AtomicLong liveConnections = new AtomicLong();

    @Inject
    public BeaconMetrics() {
        for (ProbeOutcome outcome : ProbeOutcome.values()) {
            probes.put(outcome, new AtomicLong());
        }
    }

    private static AtomicLong[] newBuckets() {
        AtomicLong[] buckets = new AtomicLong[BUCKETS_MS.length + 1];
        for (int i = 0; i < buckets.length; i++) {
            buckets[i] = new AtomicLong();
        }
        return buckets;
    }

    public void observeHttp(String method, int status, long durationMs) {
        httpRequests.computeIfAbsent(method + ":" + status, key -> new AtomicLong()).incrementAndGet();
        observe(httpDurations, httpDurationSum, httpDurationCount, durationMs);
    }

    public void observeProbe(ProbeOutcome outcome, long durationMs) {
        probes.get(outcome).incrementAndGet();
        observe(probeDurations, probeDurationSum, probeDurationCount, durationMs);
    }

    public void observeBatch(int size) {
        lastBatchSize.set(size);
    }

    public void incrementSkippedTicks() {
        skippedTicks.incrementAndGet();
    }

    public void liveConnectionOpened() {
        liveConnections.incrementAndGet();
    }

    public void liveConnectionClosed() {
        liveConnections.decrementAndGet();
    }

    private static void observe(AtomicLong[] buckets, AtomicLong sum, AtomicLong count, long durationMs) {
        int index = buckets.length - 1;
        for (int i = 0; i < BUCKETS_MS.length; i++) {
            if (durationMs <= BUCKETS_MS[i]) {
                index = i;
                break;
            }
        }
        buckets[index].incrementAndGet();
        sum.addAndGet(durationMs);
        count.incrementAndGet();
    }

    /** Текстовый формат экспозиции Prometheus. */
    public String render() {
        StringBuilder out = new StringBuilder(2048);

        out.append("# HELP beacon_http_requests_total Количество обработанных HTTP-запросов\n");
        out.append("# TYPE beacon_http_requests_total counter\n");
        httpRequests.forEach((key, value) -> {
            String[] parts = key.split(":");
            out.append("beacon_http_requests_total{method=\"").append(parts[0])
               .append("\",status=\"").append(parts[1]).append("\"} ")
               .append(value.get()).append('\n');
        });

        appendHistogram(out, "beacon_http_duration_ms", httpDurations, httpDurationSum, httpDurationCount);

        out.append("# HELP beacon_probes_total Количество выполненных проб\n");
        out.append("# TYPE beacon_probes_total counter\n");
        probes.forEach((outcome, value) ->
                out.append("beacon_probes_total{outcome=\"").append(outcome.name().toLowerCase())
                   .append("\"} ").append(value.get()).append('\n'));

        appendHistogram(out, "beacon_probe_duration_ms", probeDurations, probeDurationSum, probeDurationCount);

        out.append("# TYPE beacon_scheduler_skipped_ticks_total counter\n");
        out.append("beacon_scheduler_skipped_ticks_total ").append(skippedTicks.get()).append('\n');
        out.append("# TYPE beacon_scheduler_last_batch gauge\n");
        out.append("beacon_scheduler_last_batch ").append(lastBatchSize.get()).append('\n');
        out.append("# TYPE beacon_live_connections gauge\n");
        out.append("beacon_live_connections ").append(liveConnections.get()).append('\n');

        return out.toString();
    }

    private static void appendHistogram(
            StringBuilder out, String name, AtomicLong[] buckets, AtomicLong sum, AtomicLong count) {
        out.append("# TYPE ").append(name).append(" histogram\n");
        long cumulative = 0;
        for (int i = 0; i < BUCKETS_MS.length; i++) {
            cumulative += buckets[i].get();
            out.append(name).append("_bucket{le=\"").append(BUCKETS_MS[i]).append("\"} ")
               .append(cumulative).append('\n');
        }
        cumulative += buckets[buckets.length - 1].get();
        out.append(name).append("_bucket{le=\"+Inf\"} ").append(cumulative).append('\n');
        out.append(name).append("_sum ").append(sum.get()).append('\n');
        out.append(name).append("_count ").append(count.get()).append('\n');
    }
}
