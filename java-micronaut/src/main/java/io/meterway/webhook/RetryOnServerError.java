package io.meterway.webhook;

import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.retry.annotation.RetryPredicate;

/**
 * Повторять только то, что имеет шанс пройти со второй попытки.
 * <p>
 * Без предиката {@code @Retryable} повторяет любое {@code RuntimeException}, включая
 * {@code 400} и {@code 422}: три бесполезные попытки на каждой доставке и утроенный
 * трафик к получателю, который уже сказал «нет».
 */
public class RetryOnServerError implements RetryPredicate {

    @Override
    public boolean test(Throwable throwable) {
        if (throwable instanceof HttpClientResponseException response) {
            int code = response.getStatus().getCode();
            return code == 408 || code == 429 || code >= 500;
        }
        return true;
    }
}
