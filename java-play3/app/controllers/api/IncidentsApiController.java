package controllers.api;

import beacon.api.Views;
import beacon.domain.IncidentSeverity;
import beacon.domain.ServiceKey;
import beacon.live.LiveBus;
import beacon.live.LiveEvent;
import beacon.repository.IncidentRepository;
import beacon.repository.ServiceRepository;
import beacon.security.ApiKeyAuthenticated;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
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
public class IncidentsApiController extends Controller {

    private final IncidentRepository incidents;
    private final ServiceRepository services;
    private final LiveBus liveBus;

    @Inject
    public IncidentsApiController(IncidentRepository incidents, ServiceRepository services, LiveBus liveBus) {
        this.incidents = incidents;
        this.services = services;
        this.liveBus = liveBus;
    }

    public CompletionStage<Result> list(String slug, String state, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        boolean onlyOpen = !"all".equalsIgnoreCase(state);
        return incidents.listByOrgSlug(slug, onlyOpen, 100, 0)
                .thenApply(list -> ok(Json.toJson(list.stream().map(Views.IncidentView::of).toList())));
    }

    @BodyParser.Of(BodyParser.Json.class)
    public CompletionStage<Result> open(String slug, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        JsonNode body = request.body().asJson();
        String serviceKey = body.path("serviceKey").asText("");
        String title = body.path("title").asText("");
        String severityText = body.path("severity").asText("MAJOR").toUpperCase();
        if (serviceKey.isBlank() || title.isBlank()) {
            return CompletableFuture.completedFuture(ApiSupport.validationFailed(request, java.util.List.of(
                    "serviceKey: обязательное поле", "title: обязательное поле")));
        }
        IncidentSeverity severity;
        try {
            severity = IncidentSeverity.valueOf(severityText);
        } catch (IllegalArgumentException e) {
            return CompletableFuture.completedFuture(ApiSupport.validationFailed(request,
                    java.util.List.of("severity: допустимы MINOR, MAJOR, CRITICAL")));
        }

        return services.findByKey(slug, ServiceKey.of(serviceKey)).thenCompose(service -> {
            if (service.isEmpty()) {
                return CompletableFuture.completedFuture(ApiSupport.notFound(request, "сервис не найден"));
            }
            return incidents.openIfAbsent(service.get().id(), title, severity, false)
                    .thenApply(created -> created
                            .map(incident -> {
                                liveBus.publish(new LiveEvent.IncidentOpened(
                                        slug, serviceKey, incident.id(), incident.title(),
                                        incident.severity().name(), Instant.now()));
                                return created(Json.toJson(Views.IncidentView.of(incident)));
                            })
                            .orElseGet(() -> status(Http.Status.CONFLICT, Json.toJson(
                                    beacon.error.ApiError.of("already_open",
                                            "по сервису уже есть открытый инцидент",
                                            ApiSupport.requestId(request))))));
        });
    }

    public CompletionStage<Result> resolve(String slug, long id, Http.Request request) {
        if (ApiSupport.orgMismatch(request, slug)) {
            return CompletableFuture.completedFuture(ApiSupport.forbidden(request, slug));
        }
        return incidents.resolve(id, "Инцидент закрыт через API").thenApply(resolved -> resolved
                .map(incident -> ok(Json.toJson(Views.IncidentView.of(incident))))
                .orElseGet(() -> ApiSupport.notFound(request, "открытый инцидент " + id + " не найден")));
    }
}
