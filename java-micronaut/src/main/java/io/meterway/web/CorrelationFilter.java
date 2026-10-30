package io.meterway.web;

import io.micronaut.core.order.Ordered;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.MutableHttpResponse;
import io.micronaut.http.annotation.RequestFilter;
import io.micronaut.http.annotation.ResponseFilter;
import io.micronaut.http.annotation.ServerFilter;
import org.slf4j.MDC;

import java.util.UUID;

/**
 * Корреляционный идентификатор запроса.
 * <p>
 * Пара {@code @RequestFilter} и {@code @ResponseFilter} в одном классе заменяет
 * прежний {@code HttpServerFilter} на Publisher: методы обычные, блокировать в них нечего,
 * а Micronaut сам расставляет их в конвейере.
 */
@ServerFilter(ServerFilter.MATCH_ALL_PATTERN)
public class CorrelationFilter implements Ordered {

    public static final String HEADER = "X-Correlation-Id";
    public static final String ATTRIBUTE = "meterway.correlationId";

    @RequestFilter
    public void assignCorrelationId(HttpRequest<?> request) {
        String correlationId = request.getHeaders().get(HEADER);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }
        request.setAttribute(ATTRIBUTE, correlationId);
        MDC.put("correlationId", correlationId);
    }

    @ResponseFilter
    public void echoCorrelationId(HttpRequest<?> request, MutableHttpResponse<?> response) {
        request.getAttribute(ATTRIBUTE, String.class).ifPresent(id -> response.header(HEADER, id));
        MDC.remove("correlationId");
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
