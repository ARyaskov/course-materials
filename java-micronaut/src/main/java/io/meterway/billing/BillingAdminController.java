package io.meterway.billing;

import io.meterway.config.BillingConfiguration;
import io.meterway.domain.BillingPeriod;
import io.meterway.quota.DistributedLock;
import io.meterway.ratelimit.RateLimited;
import io.meterway.security.MeterwayPrincipal;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Post;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.authentication.Authentication;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.time.YearMonth;
import java.util.UUID;

/** Ручное управление расчётным периодом: пересчёт и повторное закрытие. */
@Controller("/v1/billing")
@Secured("ADMIN")
@ExecuteOn(TaskExecutors.BLOCKING)
@Tag(name = "Billing", description = "Управление расчётным периодом")
@SecurityRequirement(name = "bearer")
public class BillingAdminController {

    private final PeriodClosingService closing;
    private final DistributedLock lock;
    private final BillingConfiguration configuration;

    public BillingAdminController(PeriodClosingService closing,
                                  DistributedLock lock,
                                  BillingConfiguration configuration) {
        this.closing = closing;
        this.lock = lock;
        this.configuration = configuration;
    }

    @Post("/periods/{period}/close")
    @RateLimited("billing")
    @Operation(
            summary = "Закрыть расчётный период",
            description = """
                    Операция повторяема: повторный вызов возвращает alreadyClosed=true
                    и не выставляет счета заново.
                    """)
    @ApiResponse(responseCode = "200", description = "Период закрыт или уже был закрыт")
    @ApiResponse(responseCode = "409", description = "Закрытие уже выполняется на другом узле")
    public HttpResponse<ClosingReport> close(Authentication authentication, @PathVariable String period) {
        UUID tenantId = MeterwayPrincipal.tenantId(authentication);
        BillingPeriod billingPeriod = BillingPeriod.ofMonth(YearMonth.parse(period));
        String key = "meterway:lock:close:%s:%s".formatted(tenantId, billingPeriod.label());

        return lock.withLock(key, configuration.closingLockTtl(),
                        () -> closing.close(tenantId, billingPeriod))
                .map(HttpResponse::ok)
                .orElseGet(() -> HttpResponse.status(io.micronaut.http.HttpStatus.CONFLICT));
    }
}
