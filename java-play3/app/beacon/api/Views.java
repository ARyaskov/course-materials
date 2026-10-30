package beacon.api;

import beacon.domain.Check;
import beacon.domain.Incident;
import beacon.domain.MonitoredService;
import beacon.domain.ProbeResult;
import beacon.domain.ServiceStatus;
import beacon.domain.UptimeDay;
import java.time.Instant;
import java.util.List;

/**
 * DTO публичного API v1.
 *
 * <p>Доменные записи наружу не отдаются: контракт API живёт своей жизнью и меняется
 * медленнее внутренней модели. Все поля — примитивы, строки и ISO-8601 даты,
 * никаких enum'ов Java в сериализованном виде без явного name().
 */
public final class Views {

    public record ServiceView(String key, String name, String description, int position) {
        public static ServiceView of(MonitoredService service) {
            return new ServiceView(service.key().value(), service.name(), service.description(), service.position());
        }
    }

    public record CheckView(
            long id, String name, String method, String url,
            int expectedStatus, String bodyContains, int timeoutMs, int intervalSeconds, boolean enabled) {
        public static CheckView of(Check check) {
            return new CheckView(check.id(), check.name(), check.method(), check.url(),
                    check.expectedStatus(), check.bodyContains(), check.timeoutMs(),
                    check.intervalSeconds(), check.enabled());
        }
    }

    public record ProbeResultView(
            Instant startedAt, long durationMs, Integer statusCode, String outcome, String error) {
        public static ProbeResultView of(ProbeResult result) {
            return new ProbeResultView(result.startedAt(), result.durationMs(),
                    result.statusCode(), result.outcome().name().toLowerCase(), result.error());
        }
    }

    public record IncidentView(
            long id, String title, String severity, Instant openedAt, Instant resolvedAt, boolean autoCreated) {
        public static IncidentView of(Incident incident) {
            return new IncidentView(incident.id(), incident.title(),
                    incident.severity().name().toLowerCase(), incident.openedAt(),
                    incident.resolvedAt(), incident.autoCreated());
        }
    }

    public record UptimeDayView(String day, int upCount, int totalCount, long avgDurationMs) {
        public static UptimeDayView of(UptimeDay day) {
            return new UptimeDayView(day.day().toString(), day.upCount(), day.totalCount(), day.avgDurationMs());
        }
    }

    public record ServiceStatusView(
            String key, String name, String status, double uptimeRatio, long p95DurationMs,
            List<UptimeDayView> history, List<IncidentView> openIncidents) {
        public static ServiceStatusView of(ServiceStatus status) {
            return new ServiceStatusView(
                    status.service().key().value(),
                    status.service().name(),
                    status.outcome().name().toLowerCase(),
                    status.uptimeRatio(),
                    status.p95DurationMs(),
                    status.history().stream().map(UptimeDayView::of).toList(),
                    status.openIncidents().stream().map(IncidentView::of).toList());
        }
    }

    public record OrgStatusView(String org, String status, Instant generatedAt, List<ServiceStatusView> services) {}

    private Views() {}
}
