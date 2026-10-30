package controllers.admin;

import beacon.domain.Check;
import beacon.domain.ServiceKey;
import beacon.forms.CheckForm;
import beacon.parser.CheckImport;
import beacon.parser.CsvCheckParser;
import beacon.repository.CheckRepository;
import beacon.repository.ServiceRepository;
import beacon.security.AdminAuthenticated;
import beacon.status.StatusService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.data.Form;
import play.data.FormFactory;
import play.i18n.MessagesApi;
import play.libs.Scala;
import play.mvc.BodyParser;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

@AdminAuthenticated
@Singleton
public class ChecksAdminController extends Controller {

    private final CheckRepository checks;
    private final ServiceRepository services;
    private final StatusService statusService;
    private final FormFactory formFactory;
    private final MessagesApi messagesApi;

    @Inject
    public ChecksAdminController(
            CheckRepository checks,
            ServiceRepository services,
            StatusService statusService,
            FormFactory formFactory,
            MessagesApi messagesApi) {
        this.checks = checks;
        this.services = services;
        this.statusService = statusService;
        this.formFactory = formFactory;
        this.messagesApi = messagesApi;
    }

    public CompletionStage<Result> form(String slug, Http.Request request) {
        return services.listByOrgSlug(slug).thenApply(list ->
                ok(views.html.admin.checkForm.render(
                        slug, Scala.asScala(list), formFactory.form(CheckForm.class),
                        request, messagesApi.preferred(request))));
    }

    public CompletionStage<Result> create(String slug, Http.Request request) {
        Form<CheckForm> form = formFactory.form(CheckForm.class).bindFromRequest(request);
        if (form.hasErrors()) {
            return services.listByOrgSlug(slug).thenApply(list ->
                    badRequest(views.html.admin.checkForm.render(
                            slug, Scala.asScala(list), form, request, messagesApi.preferred(request))));
        }
        CheckForm data = form.get();
        return services.findByKey(slug, ServiceKey.of(data.serviceKey)).thenCompose(service -> {
            if (service.isEmpty()) {
                return CompletableFuture.completedFuture(
                        redirect(controllers.admin.routes.ChecksAdminController.form(slug))
                                .flashing("error", "Сервис " + data.serviceKey + " не найден"));
            }
            Check check = new Check(0L, service.get().id(), data.name, data.method, data.url,
                    data.expectedStatus, data.bodyContains, data.timeoutMs, data.intervalSeconds,
                    true, Instant.now(), Instant.now());
            return checks.create(check).thenCompose(created -> statusService.invalidate(slug).thenApply(ignored ->
                    redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                            .flashing("success", "Проверка «" + created.name() + "» добавлена")));
        });
    }

    public CompletionStage<Result> delete(String slug, long id, Http.Request request) {
        return checks.delete(id).thenCompose(deleted -> statusService.invalidate(slug).thenApply(ignored ->
                redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                        .flashing(deleted ? "success" : "error",
                                deleted ? "Проверка удалена" : "Проверка не найдена")));
    }

    /**
     * Импорт из CSV. Тело читает свой {@link CsvCheckParser}: контроллер получает
     * готовые строки, а превышение лимита в 2 МБ отсекается до вызова этого метода.
     */
    @BodyParser.Of(CsvCheckParser.class)
    public CompletionStage<Result> importCsv(String slug, Http.Request request) {
        CheckImport imported = request.body().as(CheckImport.class);
        if (imported == null || imported.isEmpty()) {
            return CompletableFuture.completedFuture(
                    redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                            .flashing("error", "В файле нет ни одной корректной строки"));
        }
        return services.listByOrgSlug(slug).thenCompose(list -> {
            List<CompletionStage<Integer>> stages = new ArrayList<>();
            for (var service : list) {
                List<Check> forService = imported.rows().stream()
                        .filter(row -> row.serviceKey().equals(service.key().value()))
                        .map(row -> new Check(0L, service.id(), row.name(), row.method(), row.url(),
                                row.expectedStatus(), null, row.timeoutMs(), row.intervalSeconds(),
                                true, Instant.now(), Instant.now()))
                        .toList();
                if (!forService.isEmpty()) {
                    stages.add(checks.importAll(service.id(), forService));
                }
            }
            if (stages.isEmpty()) {
                return CompletableFuture.completedFuture(
                        redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                                .flashing("error", "Ни один service_key из файла не найден"));
            }
            CompletableFuture<?>[] all = stages.stream()
                    .map(CompletionStage::toCompletableFuture)
                    .toArray(CompletableFuture[]::new);
            return CompletableFuture.allOf(all).thenCompose(ignored -> {
                int total = stages.stream().mapToInt(stage -> stage.toCompletableFuture().join()).sum();
                return statusService.invalidate(slug).thenApply(unused ->
                        redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                                .flashing("success", "Импортировано проверок: " + total
                                        + (imported.errors().isEmpty() ? ""
                                        : ", пропущено строк: " + imported.errors().size())));
            });
        });
    }
}
