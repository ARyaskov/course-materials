package filters;

import beacon.security.SecurityKeys;
import java.util.UUID;
import java.util.concurrent.CompletionStage;
import java.util.function.Function;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.stream.Materializer;
import org.slf4j.MDC;
import play.mvc.Filter;
import play.mvc.Http;
import play.mvc.Result;

/**
 * Сквозной идентификатор запроса.
 *
 * <p>Фильтр — единственное место, где его удобно завести: он видит запрос раньше роутера
 * и ответ позже контроллера. Значение кладётся в атрибуты запроса (оттуда его берут
 * контроллеры и обработчик ошибок), в MDC (оттуда — logback) и в заголовок ответа.
 */
@Singleton
public class RequestIdFilter extends Filter {

    public static final String HEADER = "X-Request-Id";

    @Inject
    public RequestIdFilter(Materializer materializer) {
        super(materializer);
    }

    @Override
    public CompletionStage<Result> apply(
            Function<Http.RequestHeader, CompletionStage<Result>> next, Http.RequestHeader request) {

        String requestId = request.header(HEADER)
                .filter(value -> !value.isBlank() && value.length() <= 64)
                .orElseGet(() -> UUID.randomUUID().toString());

        MDC.put("requestId", requestId);
        try {
            return next.apply(request.addAttr(SecurityKeys.REQUEST_ID, requestId))
                    .thenApply(result -> result.withHeader(HEADER, requestId));
        } finally {
            // MDC живёт в потоке, а продолжение выполнится в другом: чистим сразу.
            MDC.remove("requestId");
        }
    }
}
