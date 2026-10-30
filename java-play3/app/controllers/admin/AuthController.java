package controllers.admin;

import beacon.forms.LoginForm;
import beacon.repository.OrganizationRepository;
import beacon.security.AdminAuthAction;
import beacon.security.PasswordHasher;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.data.Form;
import play.data.FormFactory;
import play.i18n.MessagesApi;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

/**
 * Вход в админку.
 *
 * <p>Сессия Play — подписанная cookie, а не серверное состояние: после успешной проверки
 * пароля в неё кладутся только идентификаторы, всё остальное берётся из базы.
 */
@Singleton
public class AuthController extends Controller {

    private final FormFactory formFactory;
    private final OrganizationRepository organizations;
    private final PasswordHasher hasher;
    private final MessagesApi messagesApi;

    @Inject
    public AuthController(
            FormFactory formFactory,
            OrganizationRepository organizations,
            PasswordHasher hasher,
            MessagesApi messagesApi) {
        this.formFactory = formFactory;
        this.organizations = organizations;
        this.hasher = hasher;
        this.messagesApi = messagesApi;
    }

    public Result loginForm(Http.Request request) {
        return ok(views.html.admin.login.render(
                formFactory.form(LoginForm.class), request, messagesApi.preferred(request)));
    }

    public CompletionStage<Result> login(Http.Request request) {
        Form<LoginForm> form = formFactory.form(LoginForm.class).bindFromRequest(request);
        if (form.hasErrors()) {
            return CompletableFuture.completedFuture(
                    badRequest(views.html.admin.login.render(form, request, messagesApi.preferred(request))));
        }
        LoginForm credentials = form.get();
        return organizations.findAdminByEmail(credentials.email).thenCompose(user -> {
            if (user.isEmpty() || !hasher.verifyPassword(credentials.password, user.get().passwordHash())) {
                Form<LoginForm> failed = form.withGlobalError("error.login.invalid");
                return CompletableFuture.completedFuture(unauthorized(
                        views.html.admin.login.render(failed, request, messagesApi.preferred(request))));
            }
            return organizations.listAll().thenApply(orgs -> {
                String slug = orgs.stream()
                        .filter(org -> org.id() == user.get().orgId())
                        .map(beacon.domain.Organization::slug)
                        .findFirst()
                        .orElse("");
                return redirect(controllers.admin.routes.ServicesAdminController.list(slug))
                        .addingToSession(request, AdminAuthAction.SESSION_EMAIL, credentials.email)
                        .addingToSession(request, AdminAuthAction.SESSION_ORG, slug);
            });
        });
    }

    public Result logout(Http.Request request) {
        return redirect(controllers.admin.routes.AuthController.loginForm())
                .withNewSession()
                .flashing("info", "Вы вышли из админки");
    }
}
