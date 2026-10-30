package io.meterway.web;

import io.meterway.domain.IdempotencyConflictException;
import io.meterway.domain.MeterwayException;
import io.meterway.domain.PeriodAlreadyClosedException;
import io.meterway.domain.QuotaExceededException;
import io.meterway.domain.UnknownMeterException;
import io.meterway.ingest.BatchTooLargeException;
import io.meterway.ratelimit.RateLimitExceededException;
import io.micronaut.context.annotation.Requires;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Produces;
import io.micronaut.http.server.exceptions.ExceptionHandler;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.zalando.problem.Problem;
import org.zalando.problem.Status;
import org.zalando.problem.ThrowableProblem;

import java.net.URI;

/**
 * Единая точка превращения доменных исключений в ответ RFC 9457.
 * <p>
 * Обработчик — обычный бин: Micronaut выбирает его по параметру типа {@code ExceptionHandler},
 * поэтому отдельная регистрация не нужна. Внутренние детали наружу не попадают:
 * в ответе только тип проблемы и данные, о которых клиент и так знает.
 */
@Singleton
@Produces
@Requires(classes = {MeterwayException.class, ExceptionHandler.class})
public class MeterwayProblemHandler implements ExceptionHandler<MeterwayException, HttpResponse<?>> {

    private static final Logger LOG = LoggerFactory.getLogger(MeterwayProblemHandler.class);
    private static final String TYPE_BASE = "https://meterway.example/problems/";

    @Override
    public HttpResponse<?> handle(HttpRequest request, MeterwayException exception) {
        ThrowableProblem problem = switch (exception) {
            case QuotaExceededException quota -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + quota.problemType()))
                    .withTitle("Квота исчерпана")
                    .withStatus(Status.TOO_MANY_REQUESTS)
                    .withDetail(quota.getMessage())
                    .with("meterCode", quota.meterCode())
                    .with("limit", quota.limit())
                    .with("used", quota.used())
                    .with("retryAfterSeconds", quota.retryAfterSeconds())
                    .build();

            case IdempotencyConflictException conflict -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + conflict.problemType()))
                    .withTitle("Конфликт ключа идемпотентности")
                    .withStatus(Status.CONFLICT)
                    .withDetail(conflict.getMessage())
                    .with("idempotencyKey", conflict.idempotencyKey())
                    .build();

            case UnknownMeterException unknown -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + unknown.problemType()))
                    .withTitle("Неизвестная метрика")
                    .withStatus(Status.BAD_REQUEST)
                    .withDetail(unknown.getMessage())
                    .with("meterCode", unknown.meterCode())
                    .build();

            case BatchTooLargeException tooLarge -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + tooLarge.problemType()))
                    .withTitle("Батч слишком велик")
                    .withStatus(Status.REQUEST_ENTITY_TOO_LARGE)
                    .withDetail(tooLarge.getMessage())
                    .with("size", tooLarge.size())
                    .with("maxSize", tooLarge.maxSize())
                    .build();

            case RateLimitExceededException limited -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + limited.problemType()))
                    .withTitle("Превышен лимит обращений")
                    .withStatus(Status.TOO_MANY_REQUESTS)
                    .withDetail(limited.getMessage())
                    .with("policy", limited.policy())
                    .with("limit", limited.limit())
                    .with("retryAfterSeconds", limited.retryAfterSeconds())
                    .build();

            case PeriodAlreadyClosedException closed -> Problem.builder()
                    .withType(URI.create(TYPE_BASE + closed.problemType()))
                    .withTitle("Период уже закрыт")
                    .withStatus(Status.CONFLICT)
                    .withDetail(closed.getMessage())
                    .with("period", closed.period())
                    .build();

            default -> {
                LOG.error("Необработанное доменное исключение", exception);
                yield Problem.builder()
                        .withType(URI.create(TYPE_BASE + exception.problemType()))
                        .withTitle("Ошибка обработки")
                        .withStatus(Status.BAD_REQUEST)
                        .withDetail(exception.getMessage())
                        .build();
            }
        };

        return HttpResponse
                .status(io.micronaut.http.HttpStatus.valueOf(problem.getStatus().getStatusCode()))
                .contentType(io.micronaut.http.MediaType.APPLICATION_JSON_PROBLEM_TYPE)
                .body(problem);
    }
}
