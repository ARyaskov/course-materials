package controllers.admin;

import beacon.domain.IncidentSeverity;
import beacon.domain.ServiceKey;
import beacon.forms.IncidentForm;
import beacon.live.LiveBus;
import beacon.live.LiveEvent;
import beacon.repository.IncidentRepository;
import beacon.repository.ServiceRepository;
import beacon.security.AdminAuthenticated;
import beacon.status.StatusService;
import java.time.Instant;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.data.Form;
import play.data.FormFactory;
import play.i18n.MessagesApi;
import play.libs.Scala;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

@AdminAuthenticated
@Singleton
public class IncidentsAdminController extends Controller {

    private final IncidentRepository incidents;
    private final ServiceRepository services;
    private final StatusService statusService;
    private final LiveBus liveBus;
    private final FormFactory formFactory;
    private final MessagesApi messagesApi;

    @Inject
    public IncidentsAdminController(
            IncidentRepository incidents,
            ServiceRepository services,
            StatusService statusService,
            LiveBus liveBus,
            FormFactory formFactory,
            MessagesApi messagesApi) {
        this.incidents = incidents;
        this.services = services;
        this.statusService = statusService;
        this.liveBus = liveBus;
        this.formFactory = formFactory;
        this.messagesApi = messagesApi;
    }

    public CompletionStage<Result> list(String slug, Http.Request request) {
        return incidents.listByOrgSlug(slug, false, 50, 0).thenApply(list ->
                ok(views.html.admin.incidents.render(
                        slug, Scala.asScala(list), formFactory.form(IncidentForm.class),
                        request, messagesApi.preferred(request))));
    }

    public CompletionStage<Result> open(String slug, Http.Request request) {
        Form<IncidentForm> form = formFactory.form(IncidentForm.class).bindFromRequest(request);
        if (form.hasErrors()) {
            return incidents.listByOrgSlug(slug, false, 50, 0).thenApply(list ->
                    badRequest(views.html.admin.incidents.render(
                            slug, Scala.asScala(list), form, request, messagesApi.preferred(request))));
        }
        IncidentForm data = form.get();
        return services.findByKey(slug, ServiceKey.of(data.serviceKey)).thenCompose(service -> {
            if (service.isEmpty()) {
                return CompletableFuture.completedFuture(
                        redirect(controllers.admin.routes.IncidentsAdminController.list(slug))
                                .flashing("error", "Сервис не найден"));
            }
            return incidents.openIfAbsent(
                            service.get().id(), data.title, IncidentSeverity.valueOf(data.severity), false)
                    .thenCompose(created -> {
                        created.ifPresent(incident -> liveBus.publish(new LiveEvent.IncidentOpened(
                                slug, data.serviceKey, incident.id(), incident.title(),
                                incident.severity().name(), Instant.now())));
                        return statusService.invalidate(slug).thenApply(ignored ->
                                redirect(controllers.admin.routes.IncidentsAdminController.list(slug))
                                        .flashing(created.isPresent() ? "success" : "error",
                                                created.isPresent()
                                                        ? "Инцидент открыт"
                                                        : "По сервису уже есть открытый инцидент"));
                    });
        });
    }

    public CompletionStage<Result> resolve(String slug, long id, Http.Request request) {
        return incidents.resolve(id, "Инцидент закрыт оператором").thenCompose(resolved -> {
            resolved.ifPresent(incident -> liveBus.publish(new LiveEvent.IncidentResolved(
                    slug, "", incident.id(), Instant.now())));
            return statusService.invalidate(slug).thenApply(ignored ->
                    redirect(controllers.admin.routes.IncidentsAdminController.list(slug))
                            .flashing(resolved.isPresent() ? "success" : "error",
                                    resolved.isPresent() ? "Инцидент закрыт" : "Инцидент не найден"));
        });
    }
}
