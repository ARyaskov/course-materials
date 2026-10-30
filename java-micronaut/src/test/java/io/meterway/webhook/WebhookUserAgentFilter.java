package io.meterway.webhook;

import io.micronaut.context.annotation.Requires;
import io.micronaut.http.MutableHttpRequest;
import io.micronaut.http.annotation.ClientFilter;
import io.micronaut.http.annotation.RequestFilter;

/**
 * Проверка того, что клиент из {@link io.micronaut.http.client.HttpClientRegistry}
 * действительно проходит через клиентские фильтры.
 */
@Requires(env = "webhook-test")
@ClientFilter("/hooks/**")
public class WebhookUserAgentFilter {

    @RequestFilter
    public void identify(MutableHttpRequest<?> request) {
        request.header("User-Agent", "Meterway/1.0");
    }
}
