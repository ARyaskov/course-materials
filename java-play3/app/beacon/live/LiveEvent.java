package beacon.live;

import beacon.domain.ProbeOutcome;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import java.time.Instant;

/**
 * События, которые Beacon публикует подписчикам SSE и WebSocket.
 *
 * <p>Sealed-иерархия Java 27 плюс дискриминатор Jackson: клиент читает поле {@code type},
 * сервер обрабатывает событие через pattern matching for switch без default-ветки —
 * добавление нового варианта ломает компиляцию там, где его забыли учесть.
 */
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, include = JsonTypeInfo.As.PROPERTY, property = "type")
@JsonSubTypes({
    @JsonSubTypes.Type(value = LiveEvent.ProbeRecorded.class, name = "probe"),
    @JsonSubTypes.Type(value = LiveEvent.IncidentOpened.class, name = "incident_opened"),
    @JsonSubTypes.Type(value = LiveEvent.IncidentResolved.class, name = "incident_resolved"),
    @JsonSubTypes.Type(value = LiveEvent.Heartbeat.class, name = "heartbeat")
})
public sealed interface LiveEvent {

    /** Slug организации: по нему шина фильтрует подписчиков. */
    String orgSlug();

    Instant at();

    record ProbeRecorded(
            String orgSlug,
            String serviceKey,
            long checkId,
            ProbeOutcome outcome,
            long durationMs,
            Integer statusCode,
            Instant at) implements LiveEvent {}

    record IncidentOpened(
            String orgSlug,
            String serviceKey,
            long incidentId,
            String title,
            String severity,
            Instant at) implements LiveEvent {}

    record IncidentResolved(
            String orgSlug,
            String serviceKey,
            long incidentId,
            Instant at) implements LiveEvent {}

    record Heartbeat(String orgSlug, Instant at) implements LiveEvent {}
}
