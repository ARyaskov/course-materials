package beacon.domain;

import java.time.Duration;
import java.time.Instant;

/** Одна HTTP-проверка: что дёргаем, чего ждём в ответе и как часто повторяем. */
public record Check(
        long id,
        long serviceId,
        String name,
        String method,
        String url,
        int expectedStatus,
        String bodyContains,
        int timeoutMs,
        int intervalSeconds,
        boolean enabled,
        Instant nextRunAt,
        Instant createdAt) {

    public Duration timeout() {
        return Duration.ofMillis(timeoutMs);
    }

    public Duration interval() {
        return Duration.ofSeconds(intervalSeconds);
    }
}
