package io.meterway.web;

import io.micronaut.context.annotation.Replaces;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.MediaType;
import io.micronaut.http.MutableHttpResponse;
import io.micronaut.http.annotation.Produces;
import io.micronaut.http.server.exceptions.ExceptionHandler;
import io.micronaut.security.authentication.AuthorizationException;
import io.micronaut.security.authentication.DefaultAuthorizationExceptionHandler;
import jakarta.inject.Singleton;

/**
 * Ошибки безопасности в том же формате RFC 9457, что и все остальные.
 * <p>
 * Micronaut Security по умолчанию отвечает пустым телом, и клиенту приходится разбирать
 * два формата ошибок вместо одного.
 * <p>
 * Реализуется интерфейс, а не наследуется {@link DefaultAuthorizationExceptionHandler}:
 * у базового класса нет конструктора без аргументов, он тянет пять зависимостей ради
 * редиректов на страницу логина, которых у API нет. {@code @Replaces} не требует наследования —
 * достаточно, чтобы бин подходил во все точки внедрения замещаемого.
 * <p>
 * {@code Content-Type} выставляется вручную: {@code @Produces} без аргументов даёт
 * {@code application/json}, а единый формат ошибок требует {@code application/problem+json}.
 * <p>
 * Поле {@code detail} намеренно не заполняется: «пользователь не найден» и «неверный пароль»
 * вместе дают перебор учётных записей.
 * <p>
 * Тело — {@link ProblemResponse}, а не {@code org.zalando.problem.Problem}: последний
 * наследует {@code Exception}, и при ручном возврате в обход процессора модуля
 * micronaut-problem-json сериализуется вместе со стектрейсом. В ответе {@code 401}
 * оказывались бы имена классов, файлов и номера строк.
 */
@Singleton
@Produces
@Replaces(DefaultAuthorizationExceptionHandler.class)
public class ProblemAuthorizationExceptionHandler
        implements ExceptionHandler<AuthorizationException, MutableHttpResponse<?>> {

    private static final String TYPE_BASE = "https://meterway.example/problems/";

    @Override
    public MutableHttpResponse<?> handle(HttpRequest request, AuthorizationException exception) {
        boolean forbidden = exception.isForbidden();
        return HttpResponse
                .status(forbidden ? HttpStatus.FORBIDDEN : HttpStatus.UNAUTHORIZED)
                .header("WWW-Authenticate", "Bearer realm=\"meterway\"")
                .contentType(MediaType.APPLICATION_JSON_PROBLEM_TYPE)
                .body(ProblemResponse.of(
                        TYPE_BASE + (forbidden ? "forbidden" : "unauthenticated"),
                        forbidden ? "Доступ запрещён" : "Требуется аутентификация",
                        forbidden ? HttpStatus.FORBIDDEN.getCode() : HttpStatus.UNAUTHORIZED.getCode()));
    }
}
