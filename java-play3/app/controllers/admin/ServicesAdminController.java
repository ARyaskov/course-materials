package controllers.admin;

import beacon.domain.ServiceKey;
import beacon.forms.ServiceForm;
import beacon.repository.CheckRepository;
import beacon.repository.OrganizationRepository;
import beacon.repository.ServiceRepository;
import beacon.security.AdminAuthenticated;
import beacon.status.StatusService;
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
public class ServicesAdminController extends Controller {

    private final ServiceRepository services;
    private final CheckRepository checks;
    private final OrganizationRepository organizations;
    private final StatusService statusService;
    private final FormFactory formFactory;
    private final MessagesApi messagesApi;

    @Inject
    public ServicesAdminController(
            ServiceRepository services,
            CheckRepository checks,
            OrganizationRepository organizations,
            StatusService statusService,
            FormFactory formFactory,
            MessagesApi messagesApi) {
        this.services = services;
        this.checks = checks;
        this.organizations = organizations;
        this.statusService = statusService;
        this.formFactory = formFactory;
        this.messagesApi = messagesApi;
    }

    public CompletionStage<Result> list(String slug, Http.Request request) {
        return services.listByOrgSlug(slug).thenCompose(list ->
                checks.listByOrgSlug(slug).thenApply(allChecks ->
                        ok(views.html.admin.services.render(
                                slug, Scala.asScala(list), Scala.asScala(allChecks),
                                formFactory.form(ServiceForm.class),
                                request, messagesApi.preferred(request)))));
    }

    /**
     * Классический PRG: POST меняет данные и отвечает редиректом, сообщение уходит во flash.
     * Иначе обновление страницы в браузере повторяет создание сервиса.
     */
    public CompletionStage<Result> create(String slug, Http.Request request) {
        Form<ServiceForm> form = formFactory.form(ServiceForm.class).bindFromRequest(request);
        if (form.hasErrors()) {
            return services.listByOrgSlug(slug).thenCompose(list ->
                    checks.listByOrgSlug(slug).thenApply(allChecks ->
                            badRequest(views.html.admin.services.render(
                                    slug, Scala.asScala(list), Scala.asScala(allChecks), form, request, messagesApi.preferred(request)))));
        }
        ServiceForm data = form.get();
        return organizations.findBySlug(slug).thenCompose(org -> {
            if (org.isEmpty()) {
                return CompletableFuture.completedFuture(notFound());
            }
            return services.create(org.get().id(), ServiceKey.of(data.key), data.name, data.description, data.position)
                    .thenCompose(created -> statusService.invalidate(slug).thenApply(ignored ->
                            redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                                    .flashing("success", "Сервис " + created.name() + " создан")));
        });
    }
}
