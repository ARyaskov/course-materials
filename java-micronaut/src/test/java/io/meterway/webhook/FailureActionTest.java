package io.meterway.webhook;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.http.client.exceptions.ReadTimeoutException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Политика реакции на отказ доставки — шесть строк, фиксирующих её целиком. */
class FailureActionTest {

    @Test
    @DisplayName("Категория отказа определяет действие")
    void classifiesFailures() {
        assertEquals(FailureAction.ABANDON, FailureAction.of(response(HttpStatus.BAD_REQUEST)));
        assertEquals(FailureAction.ABANDON, FailureAction.of(response(HttpStatus.UNPROCESSABLE_ENTITY)));
        assertEquals(FailureAction.RETRY, FailureAction.of(response(HttpStatus.TOO_MANY_REQUESTS)));
        assertEquals(FailureAction.RETRY, FailureAction.of(response(HttpStatus.SERVICE_UNAVAILABLE)));
        assertEquals(FailureAction.DEACTIVATE, FailureAction.of(response(HttpStatus.GONE)));
        assertEquals(FailureAction.RETRY, FailureAction.of(ReadTimeoutException.TIMEOUT_EXCEPTION));
    }

    @Test
    @DisplayName("Предикат повторов пропускает только исправимое")
    void retryPredicate() {
        RetryOnServerError predicate = new RetryOnServerError();

        assertEquals(false, predicate.test(response(HttpStatus.BAD_REQUEST)));
        assertEquals(false, predicate.test(response(HttpStatus.GONE)));
        assertEquals(true, predicate.test(response(HttpStatus.TOO_MANY_REQUESTS)));
        assertEquals(true, predicate.test(response(HttpStatus.BAD_GATEWAY)));
        assertEquals(true, predicate.test(ReadTimeoutException.TIMEOUT_EXCEPTION));
    }

    private static HttpClientResponseException response(HttpStatus status) {
        return new HttpClientResponseException(status.getReason(), HttpResponse.status(status));
    }
}
