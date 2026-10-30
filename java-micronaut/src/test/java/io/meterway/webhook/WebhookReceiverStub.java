package io.meterway.webhook;

import io.micronaut.context.annotation.Requires;
import io.micronaut.http.HttpHeaders;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Post;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.rules.SecurityRule;
import jakarta.inject.Singleton;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Заглушка получателя вебхуков, живущая в том же контексте, что и клиент.
 * <p>
 * Отдельный процесс не нужен: контроллер поднимается вместе с тестовым сервером,
 * а накопленные запросы читаются прямо из бина. {@code @Requires(env = "webhook-test")}
 * держит заглушку вне остальных тестов — контроллер, попавший во все контексты,
 * ломает проверки маршрутизации.
 */
@Requires(env = "webhook-test")
@Secured(SecurityRule.IS_ANONYMOUS)
@Controller("/hooks")
@Singleton
public class WebhookReceiverStub {

    public record Received(Map<String, String> headers, Map<String, Object> body) {
    }

    private final List<Received> received = new CopyOnWriteArrayList<>();
    private volatile int status = 200;

    @Post("/inbox")
    HttpResponse<String> inbox(HttpHeaders headers, @Body Map<String, Object> body) {
        Map<String, String> flat = new LinkedHashMap<>();
        headers.forEach((name, values) -> flat.put(name, String.join(",", values)));
        received.add(new Received(flat, body));
        return HttpResponse.status(HttpStatus.valueOf(status)).body("");
    }

    public List<Received> received() {
        return List.copyOf(received);
    }

    public void respondWith(int status) {
        this.status = status;
    }

    public void clear() {
        received.clear();
        status = 200;
    }
}
