package beacon.domain;

import java.time.Instant;

/** Инцидент по сервису: открывается автоматически по серии падений или руками оператором. */
public record Incident(
        long id,
        long serviceId,
        String title,
        IncidentSeverity severity,
        Instant openedAt,
        Instant resolvedAt,
        boolean autoCreated) {

    public boolean isOpen() {
        return resolvedAt == null;
    }
}
