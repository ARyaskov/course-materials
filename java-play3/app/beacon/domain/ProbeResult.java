package beacon.domain;

import java.time.Instant;
import java.util.OptionalInt;

/** Результат выполнения одной пробы; строка таблицы probe_results. */
public record ProbeResult(
        long id,
        long checkId,
        Instant startedAt,
        long durationMs,
        Integer statusCode,
        ProbeOutcome outcome,
        String error) {

    public static ProbeResult unsaved(
            long checkId, Instant startedAt, long durationMs,
            Integer statusCode, ProbeOutcome outcome, String error) {
        return new ProbeResult(0L, checkId, startedAt, durationMs, statusCode, outcome, error);
    }

    public OptionalInt status() {
        return statusCode == null ? OptionalInt.empty() : OptionalInt.of(statusCode);
    }
}
