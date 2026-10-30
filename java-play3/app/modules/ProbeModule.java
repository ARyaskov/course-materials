package modules;

import beacon.incident.IncidentDetector;
import beacon.live.LiveBus;
import beacon.metrics.BeaconMetrics;
import beacon.notify.WebhookNotifier;
import beacon.probe.ProbeExecutionContext;
import beacon.probe.ProbeRunner;
import beacon.probe.ProbeScheduler;
import com.google.inject.AbstractModule;

/**
 * Фоновая часть приложения.
 *
 * <p>{@link ProbeScheduler} связан как eager singleton: без этого он был бы создан
 * только при первом обращении к нему из контроллера, то есть никогда — на него никто
 * не ссылается. Eager-биндинг и есть способ запустить фоновую работу при старте.
 */
public class ProbeModule extends AbstractModule {

    @Override
    protected void configure() {
        bind(BeaconMetrics.class).asEagerSingleton();
        bind(LiveBus.class).asEagerSingleton();
        bind(ProbeExecutionContext.class).asEagerSingleton();
        bind(ProbeRunner.class).asEagerSingleton();
        bind(WebhookNotifier.class).asEagerSingleton();
        bind(IncidentDetector.class).asEagerSingleton();
        bind(ProbeScheduler.class).asEagerSingleton();
    }
}
