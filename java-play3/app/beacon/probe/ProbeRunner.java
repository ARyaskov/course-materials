package beacon.probe;

import beacon.config.BeaconSettings;
import beacon.domain.Check;
import beacon.domain.ProbeOutcome;
import beacon.domain.ProbeResult;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.TimeoutException;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.libs.ws.WSClient;
import play.libs.ws.WSRequest;
import play.libs.ws.WSResponse;

/**
 * Выполняет одну проверку через {@link WSClient} и превращает ответ (или его отсутствие)
 * в {@link ProbeResult}. Ошибки транспорта здесь не исключение, а нормальный результат:
 * недоступный эндпоинт клиента — это ровно то, ради чего сервис существует.
 */
@Singleton
public class ProbeRunner {

    private static final Logger log = LoggerFactory.getLogger(ProbeRunner.class);

    private final WSClient ws;
    private final BeaconSettings settings;

    @Inject
    public ProbeRunner(WSClient ws, BeaconSettings settings) {
        this.ws = ws;
        this.settings = settings;
    }

    public CompletionStage<ProbeResult> run(Check check) {
        Instant startedAt = Instant.now();
        Duration timeout = check.timeoutMs() > 0
                ? check.timeout()
                : settings.probe().defaultTimeout();

        WSRequest request = ws.url(check.url())
                .setMethod(check.method())
                .setRequestTimeout(timeout)
                .addHeader("Accept", "*/*")
                .addHeader("X-Beacon-Check", Long.toString(check.id()))
                .setRequestFilter(new ProbeLogFilter(check));

        long startedNanos = System.nanoTime();
        return request.execute()
                .thenApply(response -> evaluate(check, response, startedAt, elapsedMs(startedNanos), timeout))
                .exceptionally(throwable -> failure(check, startedAt, elapsedMs(startedNanos), throwable));
    }

    private ProbeResult evaluate(Check check, WSResponse response, Instant startedAt, long durationMs, Duration timeout) {
        int status = response.getStatus();
        if (status != check.expectedStatus()) {
            return ProbeResult.unsaved(check.id(), startedAt, durationMs, status, ProbeOutcome.DOWN,
                    "ожидался статус %d, получен %d".formatted(check.expectedStatus(), status));
        }
        String expectedBody = check.bodyContains();
        if (expectedBody != null && !expectedBody.isBlank() && !response.getBody().contains(expectedBody)) {
            return ProbeResult.unsaved(check.id(), startedAt, durationMs, status, ProbeOutcome.DOWN,
                    "в теле ответа не найдено: " + expectedBody);
        }
        // Ответ корректный, но занял больше половины бюджета — сигнал деградации.
        ProbeOutcome outcome = durationMs > timeout.toMillis() / 2 ? ProbeOutcome.DEGRADED : ProbeOutcome.UP;
        return ProbeResult.unsaved(check.id(), startedAt, durationMs, status, outcome, null);
    }

    private ProbeResult failure(Check check, Instant startedAt, long durationMs, Throwable throwable) {
        Throwable cause = throwable.getCause() != null ? throwable.getCause() : throwable;
        String message = switch (cause) {
            case TimeoutException ignored -> "таймаут " + check.timeoutMs() + " мс";
            case java.net.UnknownHostException ignored -> "хост не разрешается в адрес";
            case java.net.ConnectException ignored -> "соединение не установлено";
            default -> cause.getClass().getSimpleName() + ": " + cause.getMessage();
        };
        log.debug("Проба {} завершилась ошибкой: {}", check.id(), message);
        return ProbeResult.unsaved(check.id(), startedAt, durationMs, null, ProbeOutcome.DOWN, truncate(message));
    }

    private static long elapsedMs(long startedNanos) {
        return (System.nanoTime() - startedNanos) / 1_000_000L;
    }

    private static String truncate(String value) {
        return value == null ? null : value.length() <= 500 ? value : value.substring(0, 497) + "...";
    }
}
