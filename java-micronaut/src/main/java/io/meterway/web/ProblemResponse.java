package io.meterway.web;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.micronaut.core.annotation.Nullable;
import io.micronaut.serde.annotation.Serdeable;

/**
 * Тело ответа в формате RFC 9457.
 * <p>
 * Отдельный тип, а не {@code org.zalando.problem.Problem}: тот наследует {@code Exception},
 * и Micronaut Serialization сериализует его вместе с {@code stackTrace} и
 * {@code localizedMessage}. В ответе оказываются имена классов, файлов и номера строк —
 * то есть карта внутреннего устройства приложения.
 * <p>
 * Обработчики, отдающие {@code Problem} через {@code ProblemErrorResponseProcessor} модуля
 * micronaut-problem-json, от этого свободны: там работает свой сериализатор. Ручной возврат
 * тела в обход процессора — нет, и этот тип закрывает именно такой случай.
 */
@Serdeable
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ProblemResponse(
        String type,
        String title,
        int status,
        @Nullable String detail
) {

    public static ProblemResponse of(String type, String title, int status) {
        return new ProblemResponse(type, title, status, null);
    }
}
