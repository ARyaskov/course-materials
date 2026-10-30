package io.meterway.billing;

import io.meterway.domain.BillingPeriod;
import io.meterway.persistence.entity.InvoiceEntity;
import io.meterway.persistence.entity.InvoiceLineEntity;
import io.meterway.persistence.entity.UsageAggregateEntity;
import io.meterway.persistence.repository.InvoiceLineRepository;
import io.meterway.persistence.repository.InvoiceRepository;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.meterway.ratelimit.RateLimited;
import io.meterway.security.MeterwayPrincipal;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Produces;
import io.micronaut.http.annotation.QueryValue;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.authentication.Authentication;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

/**
 * Отчётность по потреблению и счетам.
 * <p>
 * Каждый метод фильтрует по тенанту из {@link Authentication}, а не по параметру запроса:
 * идентификатор тенанта, пришедший от клиента, — это не аутентификация, а пожелание.
 */
@Controller("/v1/reports")
@Secured("CONSOLE")
@ExecuteOn(TaskExecutors.BLOCKING)
@Tag(name = "Reports", description = "Потребление и счета")
@SecurityRequirement(name = "bearer")
public class UsageReportController {

    private final UsageAggregateRepository aggregates;
    private final InvoiceRepository invoices;
    private final InvoiceLineRepository invoiceLines;

    public UsageReportController(UsageAggregateRepository aggregates,
                                 InvoiceRepository invoices,
                                 InvoiceLineRepository invoiceLines) {
        this.aggregates = aggregates;
        this.invoices = invoices;
        this.invoiceLines = invoiceLines;
    }

    @Get("/usage")
    @RateLimited("reports")
    @Operation(summary = "Агрегаты потребления за месяц")
    @ApiResponse(responseCode = "200", description = "Список агрегатов тенанта за период")
    @ApiResponse(responseCode = "400", description = "Период задан не в формате YYYY-MM")
    public List<UsageAggregateEntity> usage(Authentication authentication,
                                            @QueryValue("period") String period) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        BillingPeriod billingPeriod = BillingPeriod.ofMonth(YearMonth.parse(period));
        return aggregates.findByTenantIdAndPeriodStart(tenantId, billingPeriod.start());
    }

    @Get("/invoices")
    @RateLimited("reports")
    @Operation(summary = "Счета за месяц")
    @ApiResponse(responseCode = "200", description = "Счета тенанта за период")
    @ApiResponse(responseCode = "400", description = "Период задан не в формате YYYY-MM")
    public List<InvoiceEntity> invoices(Authentication authentication,
                                        @QueryValue("period") String period) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        BillingPeriod billingPeriod = BillingPeriod.ofMonth(YearMonth.parse(period));
        return invoices.findByTenantIdAndPeriodStart(tenantId, billingPeriod.start());
    }

    @Get("/invoices/{id}")
    @Operation(summary = "Счёт со строками")
    @ApiResponse(responseCode = "200", description = "Счёт и его строки")
    @ApiResponse(responseCode = "404", description = "Счёт не найден или принадлежит другому тенанту")
    public HttpResponse<InvoiceView> invoice(Authentication authentication, @PathVariable UUID id) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        return invoices.findByIdAndTenantId(id, tenantId)
                .map(invoice -> HttpResponse.ok(
                        new InvoiceView(invoice, invoiceLines.findByInvoiceIdOrderByPosition(invoice.id()))))
                .orElseGet(HttpResponse::notFound);
    }

    /**
     * CSV-представление того же ресурса. Content negotiation выбирает метод
     * по заголовку Accept: один URL, два формата.
     */
    @Get("/invoices/{id}")
    @Produces(MediaType.TEXT_PLAIN)
    public HttpResponse<String> invoiceCsv(Authentication authentication, @PathVariable UUID id) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        return invoices.findByIdAndTenantId(id, tenantId)
                .map(invoice -> {
                    StringBuilder csv = new StringBuilder("meter_code;description;quantity;amount_minor\n");
                    for (InvoiceLineEntity line : invoiceLines.findByInvoiceIdOrderByPosition(invoice.id())) {
                        csv.append(line.meterCode()).append(';')
                                .append(line.description().replace(';', ',')).append(';')
                                .append(line.quantity().toPlainString()).append(';')
                                .append(line.amountMinor()).append('\n');
                    }
                    return HttpResponse.ok(csv.toString());
                })
                .orElseGet(HttpResponse::notFound);
    }

    @io.micronaut.serde.annotation.Serdeable
    public record InvoiceView(InvoiceEntity invoice, List<InvoiceLineEntity> lines) {
    }
}
