package beacon.security;

import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import play.libs.Json;
import play.mvc.Action;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.Results;

/**
 * Action composition для API: проверяет ключ, кладёт организацию в атрибуты запроса
 * и только после этого зовёт следующий элемент цепочки.
 *
 * <p>Обратите внимание на возврат {@link CompletionStage}: внутри действия происходит
 * обращение к кэшу и, возможно, к базе — блокировать поток здесь нельзя.
 */
public class ApiKeyAction extends Action<ApiKeyAuthenticated> {

    private final ApiKeyService apiKeys;

    @Inject
    public ApiKeyAction(ApiKeyService apiKeys) {
        this.apiKeys = apiKeys;
    }

    @Override
    public CompletionStage<Result> call(Http.Request request) {
        return apiKeys.authenticate(request).thenCompose(authenticated -> {
            if (authenticated.isEmpty()) {
                return CompletableFuture.completedFuture(missingOrInvalidKey());
            }
            ApiKeyService.AuthenticatedOrg org = authenticated.get();
            Http.Request enriched = request
                    .addAttr(SecurityKeys.ORG_SLUG, org.slug())
                    .addAttr(SecurityKeys.API_KEY_ID, org.apiKeyId());
            return delegate.call(enriched);
        });
    }

    private Result missingOrInvalidKey() {
        ObjectNode body = Json.newObject();
        body.put("code", "unauthorized");
        body.put("message", "нужен заголовок Authorization: Bearer <prefix>.<secret>");
        return Results.unauthorized(body).withHeader(Http.HeaderNames.WWW_AUTHENTICATE, "Bearer realm=\"beacon\"");
    }
}
