package beacon.domain;

import java.time.Instant;

/** Запись в ленте инцидента: investigating / identified / monitoring / resolved. */
public record IncidentUpdate(long id, long incidentId, Instant createdAt, String status, String body) {}
