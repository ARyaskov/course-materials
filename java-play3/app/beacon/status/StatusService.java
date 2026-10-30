package beacon.status;

import beacon.config.BeaconSettings;
import beacon.domain.Check;
import beacon.domain.Incident;
import beacon.domain.MonitoredService;
import beacon.domain.ProbeOutcome;
import beacon.domain.ServiceStatus;
import beacon.domain.UptimeDay;
import beacon.repository.CheckRepository;
import beacon.repository.IncidentRepository;
import beacon.repository.ProbeResultRepository;
import beacon.repository.ServiceRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.stream.Collectors;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.cache.AsyncCacheApi;
import play.cache.NamedCache;

/**
 * Сборка состояния организации для статус-страницы и публичного API.
 *
 * <p>Запрос тяжелее остальных (агрегаты по всем проверкам), а данные меняются
 * не чаще одного тика планировщика — поэтому результат кладётся в именованный кэш
 * {@code status-cache} на {@code beacon.status-page.cache-ttl}.
 */
@Singleton
public class StatusService {

    private final ServiceRepository services;
    private final CheckRepository checks;
    private final ProbeResultRepository results;
    private final IncidentRepository incidents;
    private final AsyncCacheApi cache;
    private final BeaconSettings settings;

    @Inject
    public StatusService(
            ServiceRepository services,
            CheckRepository checks,
            ProbeResultRepository results,
            IncidentRepository incidents,
            @NamedCache("status-cache") AsyncCacheApi cache,
            BeaconSettings settings) {
        this.services = services;
        this.checks = checks;
        this.results = results;
        this.incidents = incidents;
        this.cache = cache;
        this.settings = settings;
    }

    public CompletionStage<List<ServiceStatus>> statusOf(String orgSlug) {
        int ttl = (int) Math.max(1, settings.statusPage().cacheTtl().toSeconds());
        return cache.getOrElseUpdate("status:" + orgSlug, () -> build(orgSlug), ttl);
    }

    public CompletionStage<Void> invalidate(String orgSlug) {
        return cache.remove("status:" + orgSlug).thenApply(done -> null);
    }

    private CompletionStage<List<ServiceStatus>> build(String orgSlug) {
        return services.listByOrgSlug(orgSlug)
                .thenCompose(list -> incidents.listOpenByOrgSlug(orgSlug)
                        .thenCompose(openIncidents -> {
                            Map<Long, List<Incident>> byService = openIncidents.stream()
                                    .collect(Collectors.groupingBy(Incident::serviceId));
                            List<CompletionStage<ServiceStatus>> stages = new ArrayList<>();
                            for (MonitoredService service : list) {
                                stages.add(statusOfService(
                                        service, byService.getOrDefault(service.id(), List.of())));
                            }
                            return sequence(stages);
                        }));
    }

    private CompletionStage<ServiceStatus> statusOfService(MonitoredService service, List<Incident> openIncidents) {
        int historyDays = settings.statusPage().historyDays();
        Instant from = Instant.now().minus(java.time.Duration.ofDays(1));

        return checks.listByServiceId(service.id()).thenCompose(serviceChecks -> {
            if (serviceChecks.isEmpty()) {
                return CompletableFuture.completedFuture(
                        new ServiceStatus(service, ProbeOutcome.UP, 1.0, 0L, List.of(), openIncidents));
            }
            List<CompletionStage<CheckSnapshot>> stages = new ArrayList<>();
            for (Check check : serviceChecks) {
                stages.add(snapshot(check, historyDays, from));
            }
            return sequence(stages).thenApply(snapshots -> merge(service, snapshots, openIncidents));
        });
    }

    private CompletionStage<CheckSnapshot> snapshot(Check check, int historyDays, Instant from) {
        return results.recentOutcomes(check.id(), 1).thenCompose(recent ->
                results.history(check.id(), historyDays).thenCompose(history ->
                        results.p95Duration(check.id(), from).thenApply(p95 ->
                                new CheckSnapshot(
                                        recent.isEmpty() ? ProbeOutcome.UP : recent.get(0),
                                        history,
                                        p95))));
    }

    private ServiceStatus merge(MonitoredService service, List<CheckSnapshot> snapshots, List<Incident> openIncidents) {
        ProbeOutcome worst = snapshots.stream()
                .map(CheckSnapshot::outcome)
                .max(Comparator.comparingInt(Enum::ordinal))
                .orElse(ProbeOutcome.UP);

        long up = snapshots.stream().flatMap(s -> s.history().stream()).mapToLong(UptimeDay::upCount).sum();
        long total = snapshots.stream().flatMap(s -> s.history().stream()).mapToLong(UptimeDay::totalCount).sum();
        double ratio = total == 0 ? 1.0 : (double) up / total;

        long p95 = snapshots.stream().mapToLong(CheckSnapshot::p95).max().orElse(0L);

        List<UptimeDay> history = snapshots.isEmpty() ? List.of() : snapshots.get(0).history();
        return new ServiceStatus(service, worst, ratio, p95, history, openIncidents);
    }

    private static <T> CompletionStage<List<T>> sequence(List<CompletionStage<T>> stages) {
        CompletableFuture<T>[] futures = stages.stream()
                .map(CompletionStage::toCompletableFuture)
                .toArray(CompletableFuture[]::new);
        return CompletableFuture.allOf(futures)
                .thenApply(ignored -> java.util.Arrays.stream(futures)
                        .map(CompletableFuture::join)
                        .collect(Collectors.toList()));
    }

    private record CheckSnapshot(ProbeOutcome outcome, List<UptimeDay> history, long p95) {}
}
