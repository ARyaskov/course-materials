package io.meterway.ingest;

import io.meterway.config.IngestConfiguration;
import io.meterway.observability.IngestMetrics;
import io.meterway.security.MeterwayPrincipal;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Post;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.authentication.Authentication;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.reactivestreams.Publisher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.util.UUID;

/**
 * Потоковый приём событий в формате JSON Lines.
 * <p>
 * Аннотации {@code @ExecuteOn} здесь нет намеренно: метод не выполняет работу сам, он собирает
 * цепочку и возвращает её. Блокирующая часть уводится на отдельный планировщик оператором
 * {@code subscribeOn}.
 * <p>
 * Второй аргумент {@code flatMap} — предел параллелизма, он же обратное давление: подписчик
 * запрашивает у источника ровно столько событий, сколько успевает обработать, Netty перестаёт
 * читать из сокета, и отправитель тормозит на уровне TCP.
 */
@Controller("/v1/usage-events")
@Secured("INGEST")
@Tag(name = "Ingest", description = "Приём событий потребления")
@SecurityRequirement(name = "apiKey")
public class UsageStreamController {

    private static final Logger LOG = LoggerFactory.getLogger(UsageStreamController.class);

    private final UsageIngestService service;
    private final IngestConfiguration configuration;
    private final IngestMetrics metrics;

    public UsageStreamController(UsageIngestService service,
                                 IngestConfiguration configuration,
                                 IngestMetrics metrics) {
        this.service = service;
        this.configuration = configuration;
        this.metrics = metrics;
    }

    @Post(uri = "/stream",
            consumes = MediaType.APPLICATION_JSON_STREAM,
            produces = MediaType.APPLICATION_JSON_STREAM)
    @Operation(
            summary = "Принять поток событий потребления",
            description = """
                    Формат тела — JSON Lines: один объект события на строку, без обрамляющего массива.
                    Ответ приходит в том же формате: на каждое событие своя строка с исходом.
                    Обрыв соединения не откатывает уже принятые события — повторная отправка
                    распознаётся как дубликат по ключу идемпотентности.
                    """)
    @ApiResponse(responseCode = "200", description = "Поток исходов по каждому событию")
    public Publisher<IngestOutcome> ingestStream(Authentication authentication,
                                                 @Body Publisher<UsageEventRequest> events) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);

        return Flux.from(events)
                .take(configuration.maxStreamEvents())
                .timeout(configuration.streamIdleTimeout())
                .flatMap(event -> Mono.fromCallable(() -> service.ingestOne(tenantId, event))
                                .subscribeOn(Schedulers.boundedElastic())
                                .onErrorResume(error -> Mono.just(rejected(event, error))),
                        configuration.ingestConcurrency())
                .doOnNext(metrics::recordStreamedOutcome)
                .doOnCancel(() -> LOG.info("Поток приёма отменён клиентом"))
                .checkpoint("ingest-stream");
    }

    private static IngestOutcome rejected(UsageEventRequest event, Throwable error) {
        return new IngestOutcome.Rejected(event.idempotencyKey(), "processing-failed",
                error.getClass().getSimpleName());
    }
}
