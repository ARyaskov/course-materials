package io.meterway.billing;

import io.meterway.config.BillingConfiguration;
import io.meterway.domain.BillingPeriod;
import io.meterway.event.ShutdownState;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.quota.DistributedLock;
import io.micronaut.context.annotation.Requires;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.scheduling.annotation.Scheduled;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.time.Instant;
import java.time.YearMonth;
import java.time.ZoneOffset;
import java.util.UUID;

/**
 * Фоновые операции биллинга.
 * <p>
 * Задача выполняется на каждом поде, поэтому первое, что она делает, — берёт распределённую
 * блокировку. {@code @ExecuteOn(BLOCKING)} уводит работу с планировщика: длинный пересчёт
 * не должен занимать поток, который отвечает за все остальные расписания.
 */
@Singleton
@Requires(property = "meterway.billing.scheduler.enabled", value = "true", defaultValue = "true")
public class BillingScheduler {

    private static final Logger LOG = LoggerFactory.getLogger(BillingScheduler.class);

    private final PeriodClosingService closing;
    private final TenantRepository tenants;
    private final DistributedLock lock;
    private final BillingConfiguration configuration;
    private final ShutdownState shutdown;
    private final Clock clock;

    public BillingScheduler(PeriodClosingService closing,
                            TenantRepository tenants,
                            DistributedLock lock,
                            BillingConfiguration configuration,
                            ShutdownState shutdown,
                            Clock clock) {
        this.closing = closing;
        this.tenants = tenants;
        this.lock = lock;
        this.configuration = configuration;
        this.shutdown = shutdown;
        this.clock = clock;
    }

    /** Ежечасная попытка закрыть прошедший месяц: сработает только после окончания grace-периода. */
    @Scheduled(cron = "${meterway.billing.close-cron:0 15 * * * *}")
    @ExecuteOn(TaskExecutors.BLOCKING)
    public void closePreviousPeriod() {
        Instant now = clock.instant();
        BillingPeriod previous = BillingPeriod.ofMonth(
                YearMonth.from(now.atOffset(ZoneOffset.UTC)).minusMonths(1));

        if (now.isBefore(previous.end().plus(configuration.closingGracePeriod()))) {
            LOG.debug("Период {} ещё в grace-окне, закрытие отложено", previous.label());
            return;
        }

        for (UUID tenantId : tenants.findAll().stream().map(t -> t.id()).toList()) {
            // Остановка приложения прерывает обход на границе тенанта: недоделанное
            // подхватит следующий запуск, потому что закрытие идемпотентно.
            if (shutdown.isStopping()) {
                LOG.info("Остановка: закрытие периода {} прервано", previous.label());
                return;
            }
            String key = "meterway:lock:close:%s:%s".formatted(tenantId, previous.label());
            lock.withLock(key, configuration.closingLockTtl(), () -> closing.close(tenantId, previous))
                    .ifPresentOrElse(
                            report -> LOG.info("Закрытие {}: {}", previous.label(), report),
                            () -> LOG.debug("Закрытие {} уже выполняется на другом узле", previous.label()));
        }
    }
}
