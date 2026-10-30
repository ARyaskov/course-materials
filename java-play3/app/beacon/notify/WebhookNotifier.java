package beacon.notify;

import beacon.config.BeaconSettings;
import beacon.domain.Webhook;
import beacon.live.LiveEvent;
import beacon.repository.WebhookRepository;
import com.fasterxml.jackson.databind.JsonNode;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HexFormat;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.libs.Json;
import play.libs.concurrent.Futures;
import play.libs.ws.WSClient;

/**
 * Доставка событий подписчикам организации.
 *
 * <p>Ретраи с экспоненциальным ростом паузы построены на {@link Futures#delayed},
 * а не на {@code Thread.sleep}: ожидание не занимает поток.
 */
@Singleton
public class WebhookNotifier {

    private static final Logger log = LoggerFactory.getLogger(WebhookNotifier.class);

    private final WSClient ws;
    private final WebhookRepository webhooks;
    private final Futures futures;
    private final BeaconSettings settings;

    @Inject
    public WebhookNotifier(WSClient ws, WebhookRepository webhooks, Futures futures, BeaconSettings settings) {
        this.ws = ws;
        this.webhooks = webhooks;
        this.futures = futures;
        this.settings = settings;
    }

    public void notifyOrg(String orgSlug, LiveEvent event) {
        if (!settings.notifications().enabled()) {
            return;
        }
        JsonNode payload = Json.toJson(event);
        webhooks.listEnabled(orgSlug).thenAccept(list -> {
            for (Webhook webhook : list) {
                deliver(webhook, payload, 1).exceptionally(error -> {
                    log.warn("Вебхук {} не доставлен: {}", webhook.url(), error.toString());
                    return null;
                });
            }
        });
    }

    private CompletionStage<Void> deliver(Webhook webhook, JsonNode payload, int attempt) {
        String body = Json.stringify(payload);
        return ws.url(webhook.url())
                .setRequestTimeout(settings.notifications().timeout())
                .addHeader("Content-Type", "application/json")
                .addHeader("X-Beacon-Signature", sign(webhook.secret(), body))
                .addHeader("X-Beacon-Attempt", Integer.toString(attempt))
                .post(body)
                .thenCompose(response -> {
                    if (response.getStatus() / 100 == 2) {
                        return CompletableFuture.<Void>completedFuture(null);
                    }
                    return retry(webhook, payload, attempt,
                            new IllegalStateException("HTTP " + response.getStatus()));
                })
                .exceptionallyCompose(error -> retry(webhook, payload, attempt, error));
    }

    private CompletionStage<Void> retry(Webhook webhook, JsonNode payload, int attempt, Throwable cause) {
        if (attempt >= settings.notifications().maxAttempts()) {
            log.warn("Вебхук {} исчерпал {} попыток: {}", webhook.url(), attempt, cause.toString());
            return CompletableFuture.failedFuture(cause);
        }
        Duration backoff = settings.notifications().initialBackoff().multipliedBy(1L << (attempt - 1));
        return futures.delayed(() -> deliver(webhook, payload, attempt + 1), backoff);
    }

    /** HMAC-SHA256 тела запроса: получатель проверяет, что событие пришло от Beacon. */
    static String sign(String secret, String body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(body.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException("не удалось подписать вебхук", e);
        }
    }
}
