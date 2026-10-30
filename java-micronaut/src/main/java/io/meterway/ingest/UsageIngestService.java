package io.meterway.ingest;

import io.meterway.config.IngestConfiguration;
import io.meterway.config.MeterDefinition;
import io.meterway.messaging.UsageEventMessage;
import io.meterway.messaging.UsageEventProducer;
import io.meterway.metering.MeterCatalog;
import io.meterway.metering.TimeOrderedUuid;
import io.meterway.observability.IngestMetrics;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.IdempotencyRecord;
import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.IdempotencyRepository;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.quota.QuotaDecision;
import io.meterway.quota.QuotaService;
import io.micronaut.cache.annotation.Cacheable;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Приём событий потребления.
 * <p>
 * Порядок операций внутри одного события выбран так, чтобы дешёвые отказы случались раньше дорогих:
 * каталог метрик (память), клиент (кэш), окно допустимых дат, квота (Redis),
 * и только потом захват ключа идемпотентности и запись в PostgreSQL.
 */
@Singleton
public class UsageIngestService {

    private static final Logger LOG = LoggerFactory.getLogger(UsageIngestService.class);

    /** Разделитель полей в каноническом представлении события перед хешированием. */
    private static final String FIELD_SEPARATOR = "\n";

    private final MeterCatalog catalog;
    private final CustomerRepository customers;
    private final UsageEventRepository events;
    private final IdempotencyRepository idempotency;
    private final QuotaService quotas;
    private final UsageEventProducer producer;
    private final IngestConfiguration configuration;
    private final IngestMetrics metrics;
    private final Clock clock;

    public UsageIngestService(MeterCatalog catalog,
                              CustomerRepository customers,
                              UsageEventRepository events,
                              IdempotencyRepository idempotency,
                              QuotaService quotas,
                              UsageEventProducer producer,
                              IngestConfiguration configuration,
                              IngestMetrics metrics,
                              Clock clock) {
        this.catalog = catalog;
        this.customers = customers;
        this.events = events;
        this.idempotency = idempotency;
        this.quotas = quotas;
        this.producer = producer;
        this.configuration = configuration;
        this.metrics = metrics;
        this.clock = clock;
    }

    /**
     * Батч обрабатывается по одному событию: частичный успех — штатный исход.
     * Общая транзакция на весь батч означала бы, что одно кривое событие отменяет 499 корректных.
     */
    public IngestResponse ingestBatch(UUID tenantId, List<UsageEventRequest> requests) {
        List<IngestOutcome> outcomes = new ArrayList<>(requests.size());
        for (UsageEventRequest request : requests) {
            outcomes.add(ingestOne(tenantId, request));
        }
        IngestResponse response = IngestResponse.of(outcomes);
        metrics.recordBatch(response);
        return response;
    }

    public IngestOutcome ingestOne(UUID tenantId, UsageEventRequest request) {
        Optional<MeterDefinition> meter = catalog.find(request.meterCode());
        if (meter.isEmpty()) {
            return new IngestOutcome.Rejected(request.idempotencyKey(), "unknown-meter",
                    "Метрика не зарегистрирована: " + request.meterCode());
        }

        Optional<CustomerEntity> customer = resolveCustomer(tenantId, request.customerRef());
        if (customer.isEmpty()) {
            return new IngestOutcome.Rejected(request.idempotencyKey(), "unknown-customer",
                    "Клиент не найден: " + request.customerRef());
        }

        Instant now = clock.instant();
        Optional<String> dateProblem = validateOccurredAt(request.occurredAt(), now);
        if (dateProblem.isPresent()) {
            return new IngestOutcome.Rejected(request.idempotencyKey(), "invalid-occurred-at", dateProblem.get());
        }

        CustomerEntity target = customer.get();
        boolean quotaConsumed = false;

        if (meter.get().isQuotaEnforced()) {
            QuotaDecision decision =
                    quotas.checkAndConsume(tenantId, target.id(), request.meterCode(), request.quantity());
            if (!decision.allowed()) {
                metrics.recordQuotaBlock(request.meterCode());
                return new IngestOutcome.QuotaBlocked(request.idempotencyKey(), request.meterCode(),
                        decision.limit(), decision.used(), decision.resetInSeconds());
            }
            quotaConsumed = true;
        }

        try {
            IngestOutcome outcome = store(tenantId, target, request, now);
            if (quotaConsumed && outcome instanceof IngestOutcome.Duplicate) {
                quotas.release(tenantId, target.id(), request.meterCode(), request.quantity());
            }
            return outcome;
        } catch (RuntimeException e) {
            if (quotaConsumed) {
                quotas.release(tenantId, target.id(), request.meterCode(), request.quantity());
            }
            LOG.error("Не удалось сохранить событие {}: {}", request.idempotencyKey(), e.toString());
            throw e;
        }
    }

    /**
     * Захват ключа и запись события в одной транзакции.
     * {@code claim} выполняет {@code insert ... on conflict do nothing}: ноль изменённых строк
     * означает, что ключ уже занят, и решение принимается без гонки между select и insert.
     */
    @Transactional
    protected IngestOutcome store(UUID tenantId, CustomerEntity customer, UsageEventRequest request, Instant now) {
        String fingerprint = fingerprint(request);
        UUID eventId = TimeOrderedUuid.from(request.occurredAt().toEpochMilli());

        long claimed = idempotency.claim(tenantId, request.idempotencyKey(), fingerprint,
                eventId, request.occurredAt());

        if (claimed == 0L) {
            Optional<IdempotencyRecord> existing =
                    idempotency.findByIdTenantIdAndIdIdempotencyKey(tenantId, request.idempotencyKey());
            if (existing.isEmpty()) {
                return new IngestOutcome.Conflict(request.idempotencyKey(),
                        "Ключ занят, но запись исчезла: повторите запрос");
            }
            IdempotencyRecord record = existing.get();
            if (!record.bodyFingerprint().equals(fingerprint)) {
                metrics.recordIdempotencyConflict();
                return new IngestOutcome.Conflict(request.idempotencyKey(),
                        "Ключ уже использован с другим телом события");
            }
            return new IngestOutcome.Duplicate(request.idempotencyKey(), record.eventId());
        }

        UsageEventEntity entity = new UsageEventEntity(
                eventId,
                tenantId,
                customer.id(),
                request.meterCode(),
                request.occurredAt(),
                now,
                request.quantity(),
                request.propertiesOrEmpty(),
                "api");

        events.save(entity);

        if (configuration.publishToKafka()) {
            producer.publish(UsageEventMessage.from(entity));
        }
        return new IngestOutcome.Accepted(request.idempotencyKey(), eventId);
    }

    /**
     * Клиенты меняются редко, а ищутся на каждом событии.
     * Без кэша ingest упирается в один и тот же запрос по (tenant_id, external_ref).
     */
    @Cacheable(value = "customers", parameters = {"tenantId", "externalRef"})
    protected Optional<CustomerEntity> resolveCustomer(UUID tenantId, String externalRef) {
        return customers.findByTenantIdAndExternalRef(tenantId, externalRef);
    }

    private Optional<String> validateOccurredAt(Instant occurredAt, Instant now) {
        Duration tolerance = configuration.lateEventTolerance();
        if (occurredAt.isAfter(now.plus(Duration.ofMinutes(5)))) {
            return Optional.of("Событие из будущего: " + occurredAt);
        }
        if (occurredAt.isBefore(now.minus(tolerance))) {
            return Optional.of("Событие старше допустимого окна %s: %s".formatted(tolerance, occurredAt));
        }
        return Optional.empty();
    }

    /**
     * Отпечаток тела отличает безобидный повтор от переиспользования ключа.
     * В него входит всё, что влияет на результат тарификации.
     */
    static String fingerprint(UsageEventRequest request) {
        StringBuilder canonical = new StringBuilder()
                .append(request.meterCode()).append(FIELD_SEPARATOR)
                .append(request.customerRef()).append(FIELD_SEPARATOR)
                .append(request.occurredAt().toEpochMilli()).append(FIELD_SEPARATOR)
                .append(request.quantity().stripTrailingZeros().toPlainString());

        request.propertiesOrEmpty().entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(entry -> canonical.append(FIELD_SEPARATOR)
                        .append(entry.getKey()).append('=').append(entry.getValue()));

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 недоступен", e);
        }
    }
}
