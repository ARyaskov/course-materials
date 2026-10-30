package controllers.api;

import beacon.api.Views;
import beacon.domain.ProbeOutcome;
import beacon.domain.ServiceStatus;
import beacon.repository.OrganizationRepository;
import beacon.status.StatusService;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.libs.Json;
import play.mvc.Controller;
import play.mvc.Result;

/**
 * Публичный статус организации: единственный эндпоинт API, не требующий ключа.
 * Именно его дёргают внешние дашборды и виджеты на сайтах клиентов.
 */
@Singleton
public class StatusApiController extends Controller {

    private final StatusService statusService;
    private final OrganizationRepository organizations;

    @Inject
    public StatusApiController(StatusService statusService, OrganizationRepository organizations) {
        this.statusService = statusService;
        this.organizations = organizations;
    }

    public CompletionStage<Result> status(String slug) {
        return organizations.findBySlug(slug).thenCompose(found -> {
            if (found.isEmpty()) {
                return java.util.concurrent.CompletableFuture.completedFuture(
                        notFound(Json.toJson(beacon.error.ApiError.of(
                                "not_found", "организация не найдена", "-"))));
            }
            return statusService.statusOf(slug).thenApply(statuses -> {
                Views.OrgStatusView view = new Views.OrgStatusView(
                        slug,
                        overall(statuses),
                        Instant.now(),
                        statuses.stream().map(Views.ServiceStatusView::of).toList());
                return ok(Json.toJson(view))
                        .withHeader("Cache-Control", "public, max-age=15");
            });
        });
    }

    private static String overall(List<ServiceStatus> statuses) {
        boolean anyDown = statuses.stream().anyMatch(s -> s.outcome() == ProbeOutcome.DOWN);
        boolean anyDegraded = statuses.stream().anyMatch(s -> s.outcome() == ProbeOutcome.DEGRADED);
        if (anyDown) {
            return "major_outage";
        }
        return anyDegraded ? "degraded" : "operational";
    }
}
