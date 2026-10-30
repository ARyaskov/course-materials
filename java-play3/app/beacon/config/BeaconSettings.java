package beacon.config;

import com.typesafe.config.Config;
import java.time.Duration;
import javax.inject.Inject;
import javax.inject.Singleton;

/**
 * Типобезопасный снимок секции {@code beacon} из application.conf.
 *
 * <p>Читается один раз при старте: неверное значение роняет приложение до того,
 * как оно примет первый запрос, а не на сотом обращении к API.
 */
@Singleton
public final class BeaconSettings {

    public record Probe(
            boolean enabled,
            Duration tick,
            int batchSize,
            int parallelism,
            Duration defaultTimeout,
            Duration jitter,
            int failuresToOpenIncident,
            int successesToResolveIncident) {}

    public record Notify(boolean enabled, int maxAttempts, Duration initialBackoff, Duration timeout) {}

    public record Security(Duration apiKeyCache, int rateLimitPerMinute, Duration sessionTtl) {}

    public record StatusPage(int historyDays, Duration cacheTtl) {}

    private final Probe probe;
    private final Notify notify;
    private final Security security;
    private final StatusPage statusPage;

    @Inject
    public BeaconSettings(Config root) {
        Config config = root.getConfig("beacon");

        Config p = config.getConfig("probe");
        this.probe = new Probe(
                p.getBoolean("enabled"),
                p.getDuration("tick"),
                requirePositive(p.getInt("batch-size"), "beacon.probe.batch-size"),
                requireRange(p.getInt("parallelism"), 1, 512, "beacon.probe.parallelism"),
                p.getDuration("default-timeout"),
                p.getDuration("jitter"),
                requirePositive(p.getInt("failures-to-open-incident"), "beacon.probe.failures-to-open-incident"),
                requirePositive(p.getInt("successes-to-resolve-incident"), "beacon.probe.successes-to-resolve-incident"));

        Config n = config.getConfig("notify");
        this.notify = new Notify(
                n.getBoolean("enabled"),
                requireRange(n.getInt("max-attempts"), 1, 20, "beacon.notify.max-attempts"),
                n.getDuration("initial-backoff"),
                n.getDuration("timeout"));

        Config s = config.getConfig("security");
        this.security = new Security(
                s.getDuration("api-key-cache"),
                requirePositive(s.getInt("rate-limit-per-minute"), "beacon.security.rate-limit-per-minute"),
                s.getDuration("session-ttl"));

        Config sp = config.getConfig("status-page");
        this.statusPage = new StatusPage(
                requireRange(sp.getInt("history-days"), 1, 365, "beacon.status-page.history-days"),
                sp.getDuration("cache-ttl"));
    }

    private static int requirePositive(int value, String path) {
        return requireRange(value, 1, Integer.MAX_VALUE, path);
    }

    private static int requireRange(int value, int min, int max, String path) {
        if (value < min || value > max) {
            throw new IllegalArgumentException(
                    "%s = %d, допустимый диапазон [%d, %d]".formatted(path, value, min, max));
        }
        return value;
    }

    public Probe probe() {
        return probe;
    }

    public Notify notifications() {
        return notify;
    }

    public Security security() {
        return security;
    }

    public StatusPage statusPage() {
        return statusPage;
    }
}
