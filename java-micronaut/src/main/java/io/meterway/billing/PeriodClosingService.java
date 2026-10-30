package io.meterway.billing;

import io.meterway.config.BillingConfiguration;
import io.meterway.domain.BillingPeriod;
import io.meterway.domain.Money;
import io.meterway.metering.AggregationService;
import io.meterway.persistence.entity.InvoiceEntity;
import io.meterway.persistence.entity.InvoiceLineEntity;
import io.meterway.persistence.entity.OutboxMessageEntity;
import io.meterway.persistence.entity.PeriodClosureEntity;
import io.meterway.persistence.entity.SubscriptionEntity;
import io.meterway.persistence.entity.UsageAggregateEntity;
import io.meterway.persistence.repository.InvoiceLineRepository;
import io.meterway.persistence.repository.InvoiceRepository;
import io.meterway.persistence.repository.OutboxRepository;
import io.meterway.persistence.repository.PeriodClosureRepository;
import io.meterway.persistence.repository.SubscriptionRepository;
import io.meterway.persistence.repository.UsageAggregateRepository;
import io.meterway.rating.RatedLine;
import io.meterway.rating.RatingEngine;
import io.meterway.rating.RatingResult;
import io.meterway.audit.Audited;
import io.meterway.event.DomainEventPublisher;
import io.meterway.event.PeriodClosedEvent;
import io.meterway.observability.Measured;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Закрытие расчётного периода: пересчёт агрегатов, тарификация, выставление счетов.
 * <p>
 * Операция обязана быть повторяемой. Гарантию даёт не блокировка, а журнал закрытий:
 * строка в {@code period_closures} с уникальным ключом (tenant, period_start) и проверка
 * существующего счёта по (subscription, period_start). Блокировка лишь экономит работу.
 */
@Singleton
public class PeriodClosingService {

    private static final Logger LOG = LoggerFactory.getLogger(PeriodClosingService.class);

    private final AggregationService aggregation;
    private final RatingEngine rating;
    private final SubscriptionRepository subscriptions;
    private final UsageAggregateRepository aggregates;
    private final InvoiceRepository invoices;
    private final InvoiceLineRepository invoiceLines;
    private final PeriodClosureRepository closures;
    private final OutboxRepository outbox;
    private final DomainEventPublisher events;
    private final BillingConfiguration configuration;
    private final Clock clock;

    public PeriodClosingService(AggregationService aggregation,
                                RatingEngine rating,
                                SubscriptionRepository subscriptions,
                                UsageAggregateRepository aggregates,
                                InvoiceRepository invoices,
                                InvoiceLineRepository invoiceLines,
                                PeriodClosureRepository closures,
                                OutboxRepository outbox,
                                DomainEventPublisher events,
                                BillingConfiguration configuration,
                                Clock clock) {
        this.aggregation = aggregation;
        this.rating = rating;
        this.subscriptions = subscriptions;
        this.aggregates = aggregates;
        this.invoices = invoices;
        this.invoiceLines = invoiceLines;
        this.closures = closures;
        this.outbox = outbox;
        this.events = events;
        this.configuration = configuration;
        this.clock = clock;
    }

    @Measured("meterway.billing.close.duration")
    @Audited(value = "period.close", arguments = true)
    @Transactional
    public ClosingReport close(UUID tenantId, BillingPeriod period) {
        Optional<PeriodClosureEntity> existing = closures.findByTenantIdAndPeriodStart(tenantId, period.start());
        if (existing.isPresent() && "CLOSED".equals(existing.get().status())) {
            LOG.info("Период {} тенанта {} уже закрыт, счетов {}",
                    period.label(), tenantId, existing.get().invoiceCount());
            return new ClosingReport(tenantId, period, existing.get().invoiceCount(), 0, true);
        }

        aggregation.recalculate(tenantId, period);

        List<UsageAggregateEntity> all = aggregates.findByTenantIdAndPeriodStart(tenantId, period.start());
        Map<UUID, List<UsageAggregateEntity>> byCustomer = new HashMap<>();
        for (UsageAggregateEntity aggregate : all) {
            byCustomer.computeIfAbsent(aggregate.customerId(), key -> new ArrayList<>()).add(aggregate);
        }

        int created = 0;
        int skipped = 0;

        for (SubscriptionEntity subscription : subscriptions.findByTenantIdAndStartedAtLessThanEquals(
                tenantId, period.end())) {

            if (subscription.endedAt() != null && subscription.endedAt().isBefore(period.start())) {
                continue;
            }
            if (invoices.findBySubscriptionIdAndPeriodStart(subscription.id(), period.start()).isPresent()) {
                skipped++;
                continue;
            }

            RatingResult result = rating.rate(
                    subscription.planId(),
                    byCustomer.getOrDefault(subscription.customerId(), List.of()));

            if (result.lines().isEmpty()) {
                continue;
            }
            issueInvoice(tenantId, subscription, period, result);
            created++;
        }

        PeriodClosureEntity closure = new PeriodClosureEntity(
                existing.map(PeriodClosureEntity::id).orElseGet(UUID::randomUUID),
                tenantId, period.start(), period.end(), "CLOSED",
                created + skipped, clock.instant(), null);

        if (existing.isPresent()) {
            closures.update(closure);
        } else {
            closures.save(closure);
        }

        LOG.info("Период {} тенанта {} закрыт: создано счетов {}, пропущено {}",
                period.label(), tenantId, created, skipped);

        ClosingReport report = new ClosingReport(tenantId, period, created, skipped, false);
        events.publishAfterCommit(new PeriodClosedEvent(report));
        return report;
    }

    private void issueInvoice(UUID tenantId, SubscriptionEntity subscription,
                              BillingPeriod period, RatingResult result) {
        Money total = result.total();
        UUID invoiceId = UUID.randomUUID();

        invoices.save(new InvoiceEntity(
                invoiceId, tenantId, subscription.customerId(), subscription.id(),
                period.start(), period.end(), total.currency(), total.minorUnits(),
                "ISSUED", clock.instant(), null, null));

        int position = 0;
        for (RatedLine line : result.lines()) {
            invoiceLines.save(new InvoiceLineEntity(
                    UUID.randomUUID(), invoiceId, line.meterCode(), line.description(),
                    line.quantity(), line.amount().minorUnits(), position++));
        }

        // Запись в outbox идёт той же транзакцией, что и счёт: не бывает счёта без уведомления.
        outbox.save(new OutboxMessageEntity(
                UUID.randomUUID(),
                "invoice",
                invoiceId.toString(),
                "invoice.issued",
                Map.of(
                        "invoiceId", invoiceId.toString(),
                        "tenantId", tenantId.toString(),
                        "customerId", subscription.customerId().toString(),
                        "period", period.label(),
                        "currency", total.currency(),
                        "totalMinor", total.minorUnits()),
                null, null));
    }

    @Transactional(readOnly = true)
    public List<InvoiceLineEntity> lines(UUID invoiceId) {
        return invoiceLines.findByInvoiceIdOrderByPosition(invoiceId);
    }
}
