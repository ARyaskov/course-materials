package beacon.error;

import beacon.security.SecurityKeys;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.Environment;
import play.Mode;
import play.http.HttpErrorHandler;
import play.libs.Json;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.Results;

/**
 * Один обработчик на два контура: {@code /api} отвечает JSON, остальное — HTML.
 *
 * <p>Play вызывает {@code onClientError} для 4xx, которые фреймворк сгенерировал сам
 * (нет маршрута, не разобрано тело, не прошёл биндинг параметра), и {@code onServerError}
 * для исключений, вылетевших из действия.
 */
@Singleton
public class BeaconErrorHandler implements HttpErrorHandler {

    private static final Logger log = LoggerFactory.getLogger(BeaconErrorHandler.class);

    private final Environment environment;

    @Inject
    public BeaconErrorHandler(Environment environment) {
        this.environment = environment;
    }

    @Override
    public CompletionStage<Result> onClientError(Http.RequestHeader request, int statusCode, String message) {
        String requestId = requestId(request);
        String code = switch (statusCode) {
            case Http.Status.NOT_FOUND -> "not_found";
            case Http.Status.BAD_REQUEST -> "bad_request";
            case Http.Status.FORBIDDEN -> "forbidden";
            case Http.Status.UNAUTHORIZED -> "unauthorized";
            case Http.Status.REQUEST_ENTITY_TOO_LARGE -> "payload_too_large";
            default -> "client_error";
        };
        String text = message == null || message.isBlank() ? code : message;

        if (wantsJson(request)) {
            return CompletableFuture.completedFuture(
                    Results.status(statusCode, Json.toJson(ApiError.of(code, text, requestId))));
        }
        return CompletableFuture.completedFuture(
                Results.status(statusCode, views.html.error.render(statusCode, text, requestId)));
    }

    @Override
    public CompletionStage<Result> onServerError(Http.RequestHeader request, Throwable exception) {
        String requestId = requestId(request);
        Throwable cause = unwrap(exception);
        log.error("Необработанная ошибка [{}] на {} {}", requestId, request.method(), request.uri(), cause);

        String message = environment.mode() == Mode.PROD
                ? "внутренняя ошибка, обратитесь в поддержку и назовите request id"
                : cause.getClass().getName() + ": " + cause.getMessage();

        if (wantsJson(request)) {
            return CompletableFuture.completedFuture(
                    Results.internalServerError(Json.toJson(ApiError.of("internal_error", message, requestId))));
        }
        return CompletableFuture.completedFuture(
                Results.internalServerError(views.html.error.render(500, message, requestId)));
    }

    /** CompletionStage оборачивает исключения — без разворачивания в логе окажется обёртка. */
    static Throwable unwrap(Throwable throwable) {
        Throwable current = throwable;
        while ((current instanceof java.util.concurrent.CompletionException
                || current instanceof java.util.concurrent.ExecutionException)
                && current.getCause() != null) {
            current = current.getCause();
        }
        return current;
    }

    private static boolean wantsJson(Http.RequestHeader request) {
        return request.path().startsWith("/api/")
                || request.accepts(Http.MimeTypes.JSON) && !request.accepts(Http.MimeTypes.HTML);
    }

    private static String requestId(Http.RequestHeader request) {
        return request.attrs().getOptional(SecurityKeys.REQUEST_ID).orElse("-");
    }
}
