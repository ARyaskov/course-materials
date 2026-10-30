package io.meterway.webhook;

import io.micronaut.context.annotation.Property;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.runtime.server.EmbeddedServer;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.net.URI;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Доставка вебхука проверяется целиком: подпись, заголовки, сеть, приёмник.
 * <p>
 * Задержка повторов задана выражением, поэтому тест обнуляет её через {@code @Property}
 * и не тратит полторы секунды на ожидание.
 */
@MicronautTest(environments = "webhook-test")
@Property(name = "meterway.webhooks.attempts", value = "2")
@Property(name = "meterway.webhooks.delay", value = "1ms")
class WebhookDeliveryTest {

    @Inject
    WebhookClient client;

    @Inject
    WebhookReceiverStub receiver;

    @Inject
    WebhookSigner signer;

    @Inject
    EmbeddedServer server;

    private URI inbox;

    @BeforeEach
    void reset() {
        receiver.clear();
        inbox = URI.create("http://localhost:" + server.getPort() + "/hooks/inbox");
    }

    @Test
    @DisplayName("Доставка уходит с подписью и идентификатором")
    void deliversSignedPayload() {
        Map<String, Object> payload = Map.of("type", "usage.threshold.reached", "value", 950);
        String signature = signer.sign("secret-1", 1_760_000_000L, "{}");

        HttpResponse<String> response =
                client.deliver(inbox, signature, "usage.threshold.reached", "dlv-1", payload);

        assertEquals(200, response.getStatus().getCode());
        var received = receiver.received();
        assertEquals(1, received.size());
        assertEquals(950, ((Number) received.getFirst().body().get("value")).intValue());
        assertEquals("dlv-1", received.getFirst().headers().get("Meterway-Delivery"));
        assertTrue(received.getFirst().headers().get("Meterway-Signature").startsWith("t=1760000000,v1="));
        assertEquals("Meterway/1.0", received.getFirst().headers().get("User-Agent"));
    }

    @Test
    @DisplayName("503 повторяется: attempts=2 даёт три запроса")
    void retriesOnServerError() {
        receiver.respondWith(503);

        assertThrows(HttpClientResponseException.class,
                () -> client.deliver(inbox, "sig", "test", "dlv-2", Map.of()));

        // attempts — число повторов сверх первого вызова, а не общее число запросов
        assertEquals(3, receiver.received().size());
    }

    @Test
    @DisplayName("400 не повторяется: предикат отсекает неисправимое")
    void doesNotRetryClientError() {
        receiver.respondWith(400);

        assertThrows(HttpClientResponseException.class,
                () -> client.deliver(inbox, "sig", "test", "dlv-3", Map.of()));

        assertEquals(1, receiver.received().size());
    }
}
