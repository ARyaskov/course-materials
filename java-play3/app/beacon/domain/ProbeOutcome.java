package beacon.domain;

/** Итог одной пробы. DEGRADED — ответ корректный, но медленнее порога. */
public enum ProbeOutcome {
    UP,
    DEGRADED,
    DOWN;

    public boolean isFailure() {
        return this == DOWN;
    }
}
