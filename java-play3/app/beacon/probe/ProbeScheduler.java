package beacon.probe;

import beacon.config.BeaconSettings;
import beacon.domain.CheckContext;
import beacon.domain.ProbeResult;
import beacon.incident.IncidentDetector;
import beacon.live.LiveBus;
import beacon.live.LiveEvent;
import beacon.metrics.BeaconMetrics;
import beacon.repository.CheckRepository;
import beacon.repository.ProbeResultRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.actor.ActorSystem;
import org.apache.pekko.actor.Cancellable;
import org.apache.pekko.stream.Materializer;
import org.apache.pekko.stream.javadsl.Sink;
import org.apache.pekko.stream.javadsl.Source;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.inject.ApplicationLifecycle;

/**
 * Планировщик проб: раз в {@code beacon.probe.tick} забирает пачку «созревших» проверок
 * и прогоняет их конвейером Pekko Streams с ограниченным параллелизмом.
 *
 * <p>Компонент связывается как eager singleton (см. modules.ProbeModule), поэтому
 * начинает работать при старте приложения, а не при первом HTTP-запросе.
 */
@Singleton
public class ProbeScheduler {

    private static final Logger log = LoggerFactory.getLogger(ProbeScheduler.class);

    private final CheckRepository checks;
    private final ProbeRunner runner;
    private final ProbeResultRepository results;
    private final IncidentDetector detector;
    private final LiveBus liveBus;
    private final BeaconMetrics metrics;
    private final BeaconSettings settings;
    private final Materializer materializer;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private final Cancellable schedule;

    @Inject
    public ProbeScheduler(
            ActorSystem actorSystem,
            Materializer materializer,
            CheckRepository checks,
            ProbeRunner runner,
            ProbeResultRepository results,
            IncidentDetector detector,
            LiveBus liveBus,
            BeaconMetrics metrics,
            BeaconSettings settings,
            ApplicationLifecycle lifecycle) {
        this.checks = checks;
        this.runner = runner;
        this.results = results;
        this.detector = detector;
        this.liveBus = liveBus;
        this.metrics = metrics;
        this.settings = settings;
        this.materializer = materializer;

        BeaconSettings.Probe probe = settings.probe();
        if (!probe.enabled()) {
            log.info("Планировщик проб выключен (beacon.probe.enabled = false)");
            this.schedule = null;
            return;
        }

        this.schedule = actorSystem.scheduler().scheduleAtFixedRate(
                Duration.ofSeconds(2),
                probe.tick(),
                this::tick,
                actorSystem.dispatcher());

        lifecycle.addStopHook(() -> {
            log.info("Останавливаю планировщик проб");
            schedule.cancel();
            return CompletableFuture.completedFuture(null);
        });

        log.info("Планировщик проб запущен: тик {}, параллелизм {}, пачка {}",
                probe.tick(), probe.parallelism(), probe.batchSize());
    }

    /**
     * Один цикл. Пока предыдущий не завершился, новый не стартует: иначе при недоступных
     * эндпоинтах пробы наложились бы друг на друга и очередь росла бы неограниченно.
     */
    void tick() {
        if (!running.compareAndSet(false, true)) {
            metrics.incrementSkippedTicks();
            return;
        }
        Instant now = Instant.now();
        checks.claimDue(now, settings.probe().batchSize())
                .thenCompose(this::execute)
                .whenComplete((done, error) -> {
                    running.set(false);
                    if (error != null) {
                        log.error("Цикл проб завершился ошибкой", error);
                    }
                });
    }

    private CompletionStage<org.apache.pekko.Done> execute(List<CheckContext> due) {
        if (due.isEmpty()) {
            return CompletableFuture.completedFuture(org.apache.pekko.Done.getInstance());
        }
        metrics.observeBatch(due.size());
        return Source.from(due)
                .mapAsyncUnordered(settings.probe().parallelism(), this::probe)
                .runWith(Sink.ignore(), materializer);
    }

    private CompletionStage<ProbeResult> probe(CheckContext context) {
        return jitter()
                .thenCompose(ignored -> runner.run(context.check()))
                .thenCompose(results::save)
                .thenCompose(saved -> {
                    metrics.observeProbe(saved.outcome(), saved.durationMs());
                    liveBus.publish(new LiveEvent.ProbeRecorded(
                            context.orgSlug(), context.serviceKey(), saved.checkId(),
                            saved.outcome(), saved.durationMs(), saved.statusCode(), saved.startedAt()));
                    return detector.onResult(context, saved).thenApply(v -> saved);
                });
    }

    /** Разброс старта внутри тика: без него все пробы уходят одним залпом в одну миллисекунду. */
    private CompletionStage<Void> jitter() {
        long maxMillis = settings.probe().jitter().toMillis();
        if (maxMillis <= 0) {
            return CompletableFuture.completedFuture(null);
        }
        long delay = ThreadLocalRandom.current().nextLong(maxMillis);
        return CompletableFuture.supplyAsync(() -> null,
                CompletableFuture.delayedExecutor(delay, java.util.concurrent.TimeUnit.MILLISECONDS));
    }
}
