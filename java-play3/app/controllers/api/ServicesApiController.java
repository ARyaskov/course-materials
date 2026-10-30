package controllers.api;

import beacon.api.Views;
import beacon.domain.ServiceKey;
import beacon.repository.OrganizationRepository;
import beacon.repository.ServiceRepository;
import beacon.security.ApiKeyAuthenticated;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.libs.Json;
import play.mvc.BodyParser;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

/**
 * Управление сервисами организации.
 *
 * <p>Аннотация на классе применяется ко всем действиям: без валидного ключа
 * ни одно из них не выполнится, и в атрибутах запроса гарантированно есть организация.
 */
@ApiKeyAuthenticated
@Singleton
public class ServicesApiController extends Controller {

    private final ServiceRepository services;
    private final OrganizationRepository organizations;

    @Inject
    public ServicesApiController(ServiceRepository services, OrganizationRepository organizations) {
        this.services = services;
        this.organizations = organizations;
    }

    public CompletionStage<Result> list(String slug, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        return services.listByOrgSlug(slug)
                .thenApply(list -> ok(Json.toJson(list.stream().map(Views.ServiceView::of).toList())));
    }

    public CompletionStage<Result> show(String slug, ServiceKey key, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        return services.findByKey(slug, key).thenApply(found -> found
                .map(service -> ok(Json.toJson(Views.ServiceView.of(service))))
                .orElseGet(() -> ApiSupport.notFound(request, "сервис " + key + " не найден")));
    }

    /**
     * Строгий парсер тела: {@code @BodyParser.Of(BodyParser.Json.class)} отвергает запрос
     * с чужим Content-Type до входа в метод, поэтому здесь тело гарантированно JSON.
     */
    @BodyParser.Of(BodyParser.Json.class)
    public CompletionStage<Result> create(String slug, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        JsonNode body = request.body().asJson();
        String key = body.path("key").asText("");
        String name = body.path("name").asText("");
        if (key.isBlank() || name.isBlank()) {
            return CompletableFuture.completedFuture(
                    ApiSupport.validationFailed(request, java.util.List.of(
                            "key: обязательное поле", "name: обязательное поле")));
        }
        ServiceKey serviceKey;
        try {
            serviceKey = ServiceKey.of(key);
        } catch (IllegalArgumentException e) {
            return CompletableFuture.completedFuture(
                    ApiSupport.validationFailed(request, java.util.List.of("key: " + e.getMessage())));
        }
        String description = body.path("description").asText(null);
        int position = body.path("position").asInt(0);

        return organizations.findBySlug(slug).thenCompose(org -> {
            if (org.isEmpty()) {
                return CompletableFuture.completedFuture(ApiSupport.notFound(request, "организация не найдена"));
            }
            return services.create(org.get().id(), serviceKey, name, description, position)
                    .thenApply(created -> created(Json.toJson(Views.ServiceView.of(created)))
                            .withHeader(Http.HeaderNames.LOCATION,
                                    controllers.api.routes.ServicesApiController.show(slug, serviceKey).url()));
        });
    }
}
