package io.meterway.ingest;

import io.meterway.config.IngestConfiguration;
import io.meterway.security.MeterwayPrincipal;
import io.micronaut.http.HttpHeaders;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Post;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.authentication.Authentication;
import io.micronaut.validation.Validated;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/**
 * Приём событий потребления.
 * <p>
 * {@code @ExecuteOn(BLOCKING)} обязателен: внутри JDBC и синхронный Redis.
 * Без него обработка выполнилась бы на потоке event loop Netty и остановила бы весь сервер
 * при первом же ожидании соединения из пула.
 */
@Controller("/v1/usage-events")
@Secured("INGEST")
@Validated
@ExecuteOn(TaskExecutors.BLOCKING)
@Tag(name = "Ingest", description = "Приём событий потребления")
@SecurityRequirement(name = "apiKey")
public class UsageIngestController {

    private final UsageIngestService service;
    private final IngestConfiguration configuration;

    public UsageIngestController(UsageIngestService service, IngestConfiguration configuration) {
        this.service = service;
        this.configuration = configuration;
    }

    @Post(consumes = MediaType.APPLICATION_JSON, produces = MediaType.APPLICATION_JSON)
    @Operation(
            summary = "Принять одно событие потребления",
            description = """
                    Событие идентифицируется ключом идемпотентности в пределах тенанта.
                    Повтор с тем же ключом и телом возвращает 200 и тот же идентификатор события;
                    тот же ключ с другим телом — 409.
                    """)
    @ApiResponse(responseCode = "202", description = "Событие принято, Location указывает на ресурс")
    @ApiResponse(responseCode = "200", description = "Событие уже было принято ранее с тем же телом")
    @ApiResponse(responseCode = "409", description = "Ключ идемпотентности занят событием с другим телом")
    @ApiResponse(responseCode = "429", description = "Квота исчерпана, см. заголовок Retry-After")
    @ApiResponse(responseCode = "400", description = "Событие отклонено: метрика, клиент или дата")
    public HttpResponse<IngestOutcome> ingest(Authentication authentication,
                                              @Body @Valid UsageEventRequest request) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        IngestOutcome outcome = service.ingestOne(tenantId, request);
        return switch (outcome) {
            case IngestOutcome.Accepted accepted -> HttpResponse
                    .accepted()
                    .header(HttpHeaders.LOCATION, "/v1/usage-events/" + accepted.eventId())
                    .body(outcome);
            case IngestOutcome.Duplicate ignored -> HttpResponse.ok(outcome);
            case IngestOutcome.Conflict ignored -> HttpResponse.status(HttpStatus.CONFLICT).body(outcome);
            case IngestOutcome.QuotaBlocked blocked -> HttpResponse
                    .status(HttpStatus.TOO_MANY_REQUESTS)
                    .header("Retry-After", String.valueOf(blocked.retryAfterSeconds()))
                    .header("X-RateLimit-Limit", String.valueOf(blocked.limit()))
                    .header("X-RateLimit-Remaining", String.valueOf(Math.max(0, blocked.limit() - blocked.used())))
                    .body(outcome);
            case IngestOutcome.Rejected ignored -> HttpResponse.badRequest(outcome);
        };
    }

    /**
     * Батчевый приём. Ответ 207 не используется: клиенту проще разобрать один формат,
     * в котором каждому событию соответствует свой исход.
     */
    @Post(uri = "/batch", consumes = MediaType.APPLICATION_JSON, produces = MediaType.APPLICATION_JSON)
    @Operation(
            summary = "Принять батч событий потребления",
            description = """
                    Частичный успех — штатный исход: ответ содержит исход по каждому событию.
                    Код 202 означает, что отклонённых событий нет, 200 — что они есть.
                    """)
    @ApiResponse(responseCode = "202", description = "Все события батча приняты")
    @ApiResponse(responseCode = "200", description = "Часть событий отклонена, разбор в теле ответа")
    @ApiResponse(responseCode = "413", description = "Батч превышает настроенный предел")
    public HttpResponse<IngestResponse> ingestBatch(Authentication authentication,
                                                    @Body @Valid UsageEventBatchRequest request) {
        List<UsageEventRequest> events = request.events();
        if (events.size() > configuration.maxBatchSize()) {
            throw new BatchTooLargeException(events.size(), configuration.maxBatchSize());
        }
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        IngestResponse response = service.ingestBatch(tenantId, events);
        return response.hasFailures()
                ? HttpResponse.ok(response)
                : HttpResponse.accepted().body(response);
    }
}
