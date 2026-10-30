package controllers.api;

import beacon.api.CreateCheckRequest;
import beacon.api.Views;
import beacon.domain.Check;
import beacon.domain.ServiceKey;
import beacon.domain.TimeRange;
import beacon.repository.CheckRepository;
import beacon.repository.ProbeResultRepository;
import beacon.repository.ServiceRepository;
import beacon.security.ApiKeyAuthenticated;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.libs.Json;
import play.mvc.BodyParser;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

@ApiKeyAuthenticated
@Singleton
public class ChecksApiController extends Controller {

    private final CheckRepository checks;
    private final ServiceRepository services;
    private final ProbeResultRepository results;

    @Inject
    public ChecksApiController(CheckRepository checks, ServiceRepository services, ProbeResultRepository results) {
        this.checks = checks;
        this.services = services;
        this.results = results;
    }

    public CompletionStage<Result> list(String slug, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        return checks.listByOrgSlug(slug)
                .thenApply(list -> ok(Json.toJson(list.stream().map(Views.CheckView::of).toList())));
    }

    /**
     * Разбор тела в запись Java 27 и ручная валидация: Jackson отвечает за форму,
     * доменные ограничения проверяет сам объект запроса.
     */
    @BodyParser.Of(BodyParser.Json.class)
    public CompletionStage<Result> create(String slug, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        CreateCheckRequest command;
        try {
            command = Json.fromJson(request.body().asJson(), CreateCheckRequest.class);
        } catch (RuntimeException e) {
            return CompletableFuture.completedFuture(
                    ApiSupport.badRequest(request, "тело не разобрано: " + e.getMessage()));
        }
        List<String> problems = command.validate();
        if (!problems.isEmpty()) {
            return CompletableFuture.completedFuture(ApiSupport.validationFailed(request, problems));
        }

        return services.findByKey(slug, ServiceKey.of(command.serviceKey())).thenCompose(service -> {
            if (service.isEmpty()) {
                return CompletableFuture.completedFuture(
                        ApiSupport.notFound(request, "сервис " + command.serviceKey() + " не найден"));
            }
            Check check = new Check(
                    0L, service.get().id(), command.name(), command.methodOrDefault(), command.url(),
                    command.expectedStatusOrDefault(), command.bodyContains(), command.timeoutOrDefault(),
                    command.intervalOrDefault(), true, Instant.now(), Instant.now());
            return checks.create(check)
                    .thenApply(created -> created(Json.toJson(Views.CheckView.of(created))));
        });
    }

    public CompletionStage<Result> delete(String slug, long id, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        return checks.delete(id).thenApply(deleted -> deleted
                ? noContent()
                : ApiSupport.notFound(request, "проверка " + id + " не найдена"));
    }

    public CompletionStage<Result> results(String slug, long id, TimeRange range, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        Instant from = range.from(Instant.now());
        return results.listByCheck(id, from, 1000)
                .thenApply(list -> ok(Json.toJson(list.stream().map(Views.ProbeResultView::of).toList()))
                        .withHeader("X-Beacon-Range", range.toString()));
    }
}
