package controllers.api;

import beacon.error.ApiError;
import beacon.security.SecurityKeys;
import java.util.List;
import play.libs.Json;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.Results;

/**
 * Общие для всех API-контроллеров ответы. Формат ошибки задан один раз здесь,
 * поэтому клиент разбирает любой отказ одинаково.
 */
final class ApiSupport {

    static String requestId(Http.Request request) {
        return request.attrs().getOptional(SecurityKeys.REQUEST_ID).orElse("-");
    }

    /** Ключ выдан организации A, а запрос идёт к организации B — это 403, а не 404. */
    static boolean orgMismatch(Http.Request request, String slug) {
        return !request.attrs().getOptional(SecurityKeys.ORG_SLUG)
                .map(slug::equals)
                .orElse(false);
    }

    static Result forbidden(Http.Request request, String slug) {
        return Results.forbidden(Json.toJson(ApiError.of(
                "forbidden", "ключ не даёт доступа к организации " + slug, requestId(request))));
    }

    static Result notFound(Http.Request request, String what) {
        return Results.notFound(Json.toJson(ApiError.of("not_found", what, requestId(request))));
    }

    static Result badRequest(Http.Request request, String message) {
        return Results.badRequest(Json.toJson(ApiError.of("bad_request", message, requestId(request))));
    }

    static Result validationFailed(Http.Request request, List<String> problems) {
        List<ApiError.FieldError> fields = problems.stream()
                .map(problem -> {
                    int colon = problem.indexOf(':');
                    return colon > 0
                            ? new ApiError.FieldError(problem.substring(0, colon), problem.substring(colon + 1).trim())
                            : new ApiError.FieldError("", problem);
                })
                .toList();
        return Results.status(Http.Status.UNPROCESSABLE_ENTITY, Json.toJson(
                ApiError.validation("тело запроса не прошло проверку", requestId(request), fields)));
    }

    private ApiSupport() {}
}
