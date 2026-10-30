package beacon.domain;

import java.util.List;

/** Агрегированное состояние сервиса для статус-страницы и публичного API. */
public record ServiceStatus(
        MonitoredService service,
        ProbeOutcome outcome,
        double uptimeRatio,
        long p95DurationMs,
        List<UptimeDay> history,
        List<Incident> openIncidents) {

    public boolean operational() {
        return outcome == ProbeOutcome.UP && openIncidents.isEmpty();
    }
}
