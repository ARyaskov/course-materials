package beacon.incident;

import beacon.config.BeaconSettings;
import beacon.domain.CheckContext;
import beacon.domain.IncidentSeverity;
import beacon.domain.ProbeOutcome;
import beacon.domain.ProbeResult;
import beacon.live.LiveBus;
import beacon.live.LiveEvent;
import beacon.notify.WebhookNotifier;
import beacon.repository.IncidentRepository;
import beacon.repository.ProbeResultRepository;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Превращает поток результатов проб в инциденты.
 *
 * <p>Правило простое и осознанно консервативное: инцидент открывается после N подряд
 * неудачных проб и закрывается после M подряд удачных. Одна случайная сетевая ошибка
 * не должна поднимать статус-страницу «красным».
 */
@Singleton
public class IncidentDetector {

    private static final Logger log = LoggerFactory.getLogger(IncidentDetector.class);

    private final ProbeResultRepository results;
    private final IncidentRepository incidents;
    private final LiveBus liveBus;
    private final WebhookNotifier notifier;
    private final BeaconSettings settings;

    @Inject
    public IncidentDetector(
            ProbeResultRepository results,
            IncidentRepository incidents,
            LiveBus liveBus,
            WebhookNotifier notifier,
            BeaconSettings settings) {
        this.results = results;
        this.incidents = incidents;
        this.liveBus = liveBus;
        this.notifier = notifier;
        this.settings = settings;
    }

    public CompletionStage<Void> onResult(CheckContext context, ProbeResult result) {
        int toOpen = settings.probe().failuresToOpenIncident();
        int toResolve = settings.probe().successesToResolveIncident();
        int window = Math.max(toOpen, toResolve);

        return results.recentOutcomes(result.checkId(), window)
                .thenCompose(recent -> {
                    if (result.outcome() == ProbeOutcome.DOWN && allDown(recent, toOpen)) {
                        return open(context);
                    }
                    if (result.outcome() != ProbeOutcome.DOWN && allUp(recent, toResolve)) {
                        return resolve(context);
                    }
                    return java.util.concurrent.CompletableFuture.completedFuture(null);
                });
    }

    private static boolean allDown(List<ProbeOutcome> recent, int required) {
        return recent.size() >= required
                && recent.subList(0, required).stream().allMatch(ProbeOutcome::isFailure);
    }

    private static boolean allUp(List<ProbeOutcome> recent, int required) {
        return recent.size() >= required
                && recent.subList(0, required).stream().noneMatch(ProbeOutcome::isFailure);
    }

    private CompletionStage<Void> open(CheckContext context) {
        String title = "Сервис %s не отвечает".formatted(context.serviceKey());
        return incidents
                .openIfAbsent(context.check().serviceId(), title, IncidentSeverity.MAJOR, true)
                .thenAccept(created -> created.ifPresent(incident -> {
                    log.warn("Открыт инцидент {} по сервису {}", incident.id(), context.serviceKey());
                    LiveEvent event = new LiveEvent.IncidentOpened(
                            context.orgSlug(), context.serviceKey(), incident.id(),
                            incident.title(), incident.severity().name(), Instant.now());
                    liveBus.publish(event);
                    notifier.notifyOrg(context.orgSlug(), event);
                }));
    }

    private CompletionStage<Void> resolve(CheckContext context) {
        return incidents.findOpenByService(context.check().serviceId())
                .thenCompose(open -> {
                    if (open.isEmpty() || !open.get().autoCreated()) {
                        return java.util.concurrent.CompletableFuture.<Void>completedFuture(null);
                    }
                    return incidents
                            .resolve(open.get().id(), "Проверки снова проходят, инцидент закрыт автоматически.")
                            .thenAccept(resolved -> resolved.ifPresent(incident -> {
                                log.info("Закрыт инцидент {} по сервису {}", incident.id(), context.serviceKey());
                                LiveEvent event = new LiveEvent.IncidentResolved(
                                        context.orgSlug(), context.serviceKey(), incident.id(), Instant.now());
                                liveBus.publish(event);
                                notifier.notifyOrg(context.orgSlug(), event);
                            }));
                });
    }
}
