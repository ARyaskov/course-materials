package io.meterway.webhook;

import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.MediaType;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.HttpClientRegistry;
import io.micronaut.retry.annotation.Retryable;
import jakarta.inject.Singleton;

import java.net.URI;
import java.util.Map;

/**
 * Отправка одного вебхука.
 * <p>
 * Обёртка над низкоуровневым клиентом, а не декларативный интерфейс: адрес получателя
 * приходит из базы и у каждого подписчика свой, а базовый адрес {@code @Client}
 * фиксируется на этапе компиляции. {@code @Retryable} работает и здесь — перехватчик
 * вешается на любой бин, а не только на {@code @Client}.
 * <p>
 * Клиент берётся из {@link HttpClientRegistry}, а не создаётся статическим
 * {@code HttpClient.create}: клиент из реестра управляется контекстом и проходит
 * через зарегистрированные {@code @ClientFilter}.
 * <p>
 * {@code @CircuitBreaker} на этом месте был бы вреден: состояние размыкателя общее для
 * всех получателей, и один сломанный подписчик заблокировал бы доставку остальным.
 * Долгий простой получателя обрабатывает расписание в базе ({@link WebhookDispatcher}),
 * потому что оно переживает перезапуск приложения.
 */
@Singleton
public class WebhookClient {

    private final HttpClient httpClient;

    public WebhookClient(HttpClientRegistry<HttpClient> registry) {
        this.httpClient = registry.getDefaultClient();
    }

    /**
     * Значения заданы выражениями, чтобы тест мог обнулить задержку: иначе проверка
     * политики повторов стоила бы полторы секунды ожидания.
     */
    @Retryable(attempts = "${meterway.webhooks.attempts:3}",
               delay = "${meterway.webhooks.delay:500ms}",
               multiplier = "2.0",
               predicate = RetryOnServerError.class)
    public HttpResponse<String> deliver(URI url,
                                        String signature,
                                        String eventType,
                                        String deliveryId,
                                        Map<String, Object> payload) {
        HttpRequest<Map<String, Object>> request = HttpRequest.POST(url, payload)
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON)
                .header("Meterway-Signature", signature)
                .header("Meterway-Event", eventType)
                .header("Meterway-Delivery", deliveryId);

        return httpClient.toBlocking().exchange(request, String.class);
    }
}
