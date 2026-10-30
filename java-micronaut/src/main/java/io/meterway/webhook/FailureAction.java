package io.meterway.webhook;

import io.micronaut.http.client.exceptions.HttpClientResponseException;

/**
 * Что делать с неудачной доставкой.
 * <p>
 * Решение принимается по категории ошибки, а не по коду: повторять {@code 400}
 * бессмысленно, {@code 503} — обязательно, а {@code 410} означает, что получатель
 * прекратил интеграцию и повторы надо остановить навсегда.
 */
public enum FailureAction {

    /** Повторить позже по расписанию. */
    RETRY,

    /** Прекратить попытки: ошибка сама не исправится. */
    ABANDON,

    /** Отключить эндпоинт: получатель сообщил о прекращении интеграции. */
    DEACTIVATE;

    public static FailureAction of(Throwable error) {
        if (error instanceof HttpClientResponseException response) {
            return ofStatus(response.getStatus().getCode());
        }
        return RETRY;
    }

    public static FailureAction ofStatus(int code) {
        if (code == 410) {
            return DEACTIVATE;
        }
        if (code == 408 || code == 429 || code >= 500) {
            return RETRY;
        }
        if (code < 400) {
            return RETRY;
        }
        return ABANDON;
    }
}
