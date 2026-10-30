package io.meterway.web;

import io.meterway.ingest.IngestOutcome;
import io.meterway.ingest.UsageEventRequest;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.MediaType;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.annotation.Client;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Единый формат ошибок — то, что легче всего потерять при обновлении версии фреймворка.
 * Тест на формат ответа безопасности важнее теста на формат ошибки валидации:
 * подмена обработчика Micronaut Security теряется молча.
 */
@MicronautTest(transactional = false)
class ContractErrorFormatTest {

    @Inject
    @Client("/")
    HttpClient client;

    private UsageEventRequest event() {
        return new UsageEventRequest("fmt-" + UUID.randomUUID(), "api.requests", "cust-north",
                Instant.now().minusSeconds(60), BigDecimal.ONE, Map.of());
    }

    @Test
    @DisplayName("Ошибка аутентификации приходит в формате problem+json")
    void authErrorIsProblem() {
        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(
                        HttpRequest.POST("/v1/usage-events", event()), IngestOutcome.class));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals(MediaType.APPLICATION_JSON_PROBLEM_TYPE,
                error.getResponse().getContentType().orElseThrow());

        Map<String, Object> problem = error.getResponse().getBody(Map.class).orElseThrow();
        assertEquals("https://meterway.example/problems/unauthenticated", problem.get("type"));
    }
}
