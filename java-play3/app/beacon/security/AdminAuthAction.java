package beacon.security;

import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import play.mvc.Action;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.Results;

/**
 * Сессия админки: Play кладёт её в подписанную cookie, поэтому проверка не ходит в базу.
 * В атрибуты запроса попадает slug организации — контроллеры дальше работают с ним,
 * а не с содержимым сессии.
 */
public class AdminAuthAction extends Action<AdminAuthenticated> {

    public static final String SESSION_EMAIL = "adminEmail";
    public static final String SESSION_ORG = "adminOrg";

    @Inject
    public AdminAuthAction() {}

    @Override
    public CompletionStage<Result> call(Http.Request request) {
        Optional<String> email = request.session().get(SESSION_EMAIL);
        Optional<String> org = request.session().get(SESSION_ORG);
        if (email.isEmpty() || org.isEmpty()) {
            return CompletableFuture.completedFuture(
                    Results.redirect(controllers.admin.routes.AuthController.loginForm()));
        }
        return delegate.call(request.addAttr(SecurityKeys.ORG_SLUG, org.get()));
    }
}
