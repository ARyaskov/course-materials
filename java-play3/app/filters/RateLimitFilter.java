package filters;

import beacon.config.BeaconSettings;
import beacon.error.ApiError;
import beacon.security.SecurityKeys;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.stream.Materializer;
import play.libs.Json;
import play.mvc.Filter;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.Results;

/**
 * Ограничение частоты обращений к API: фиксированное окно в одну минуту на ключ.
 *
 * <p>Ключ — идентификатор API-ключа, если запрос аутентифицирован, иначе адрес клиента.
 * За обратным прокси адрес берётся из {@code X-Forwarded-For}, но только если
 * прокси описан в {@code play.http.forwarded.trustedProxies}.
 */
@Singleton
public class RateLimitFilter extends Filter {

    private static final Duration WINDOW = Duration.ofMinutes(1);

    private record Counter(Instant windowStart, int count) {}

    private final Map<String, Counter> counters = new ConcurrentHashMap<>();
    private final BeaconSettings settings;

    @Inject
    public RateLimitFilter(Materializer materializer, BeaconSettings settings) {
        super(materializer);
        this.settings = settings;
    }

    @Override
    public CompletionStage<Result> apply(
            Function<Http.RequestHeader, CompletionStage<Result>> next, Http.RequestHeader request) {

        if (!request.path().startsWith("/api/")) {
            return next.apply(request);
        }

        int limit = settings.security().rateLimitPerMinute();
        String key = keyOf(request);
        Instant now = Instant.now();

        Counter counter = counters.compute(key, (ignored, current) -> {
            if (current == null || current.windowStart().plus(WINDOW).isBefore(now)) {
                return new Counter(now, 1);
            }
            return new Counter(current.windowStart(), current.count() + 1);
        });

        if (counter.count() > limit) {
            long retryAfter = Math.max(1, Duration.between(now, counter.windowStart().plus(WINDOW)).toSeconds());
            ApiError error = ApiError.of("rate_limited", "превышен лимит " + limit + " запросов в минуту",
                    request.attrs().getOptional(SecurityKeys.REQUEST_ID).orElse("-"));
            return CompletableFuture.completedFuture(
                    Results.status(Http.Status.TOO_MANY_REQUESTS, Json.toJson(error))
                            .withHeader("Retry-After", Long.toString(retryAfter))
                            .withHeader("X-RateLimit-Limit", Integer.toString(limit))
                            .withHeader("X-RateLimit-Remaining", "0"));
        }

        int remaining = Math.max(0, limit - counter.count());
        return next.apply(request).thenApply(result -> result
                .withHeader("X-RateLimit-Limit", Integer.toString(limit))
                .withHeader("X-RateLimit-Remaining", Integer.toString(remaining)));
    }

    private static String keyOf(Http.RequestHeader request) {
        return request.attrs().getOptional(SecurityKeys.API_KEY_ID)
                .map(id -> "key:" + id)
                .orElseGet(() -> "ip:" + request.remoteAddress());
    }
}
