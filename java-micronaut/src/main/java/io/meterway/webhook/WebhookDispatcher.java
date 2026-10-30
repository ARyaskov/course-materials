package io.meterway.webhook;

import io.meterway.config.WebhookConfiguration;
import io.meterway.persistence.entity.OutboxMessageEntity;
import io.meterway.persistence.entity.WebhookDeliveryEntity;
import io.meterway.persistence.entity.WebhookEndpointEntity;
import io.meterway.persistence.repository.WebhookDeliveryRepository;
import io.meterway.persistence.repository.WebhookEndpointRepository;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.scheduling.annotation.Scheduled;
import io.micronaut.serde.ObjectMapper;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.net.URI;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Постановка и доставка вебхуков.
 * <p>
 * Доставка отделена от постановки: сообщение сначала становится строкой в таблице,
 * и только потом уходит в сеть. Иначе отказ чужого сервиса ронял бы транзакцию,
 * в которой выставлялся счёт.
 */
@Singleton
public class WebhookDispatcher {

    private static final Logger LOG = LoggerFactory.getLogger(WebhookDispatcher.class);

    private final WebhookEndpointRepository endpoints;
    private final WebhookDeliveryRepository deliveries;
    private final WebhookClient client;
    private final WebhookSigner signer;
    private final WebhookConfiguration configuration;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public WebhookDispatcher(WebhookEndpointRepository endpoints,
                             WebhookDeliveryRepository deliveries,
                             WebhookClient client,
                             WebhookSigner signer,
                             WebhookConfiguration configuration,
                             ObjectMapper objectMapper,
                             Clock clock) {
        this.endpoints = endpoints;
        this.deliveries = deliveries;
        this.client = client;
        this.signer = signer;
        this.configuration = configuration;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    /** Раскладывает сообщение outbox по подписанным эндпоинтам тенанта. */
    @Transactional
    public void enqueue(OutboxMessageEntity message) {
        if (!configuration.enabled()) {
            return;
        }
        Object tenantId = message.payload().get("tenantId");
        if (tenantId == null) {
            LOG.warn("В сообщении outbox {} нет tenantId, доставка пропущена", message.id());
            return;
        }
        UUID tenant = UUID.fromString(tenantId.toString());

        for (WebhookEndpointEntity endpoint : endpoints.findByTenantIdAndActiveTrue(tenant)) {
            boolean subscribed = endpoint.eventTypes().length == 0
                    || Arrays.asList(endpoint.eventTypes()).contains(message.eventType());
            if (!subscribed) {
                continue;
            }
            deliveries.save(new WebhookDeliveryEntity(
                    UUID.randomUUID(), endpoint.id(), message.eventType(), message.payload(),
                    "PENDING", 0, clock.instant(), null, null, null));
        }
    }

    /**
     * Разбор очереди доставок. Строки берутся с {@code skip locked},
     * поэтому несколько подов работают параллельно и не пересекаются.
     */
    @Scheduled(fixedDelay = "${meterway.webhooks.poll-interval:10s}")
    @ExecuteOn(TaskExecutors.BLOCKING)
    public void deliverDue() {
        if (!configuration.enabled()) {
            return;
        }
        for (WebhookDeliveryEntity delivery : lockDue()) {
            attempt(delivery);
        }
    }

    @Transactional
    protected List<WebhookDeliveryEntity> lockDue() {
        return deliveries.lockDue(clock.instant(), 50);
    }

    void attempt(WebhookDeliveryEntity delivery) {
        WebhookEndpointEntity endpoint = endpoints.findById(delivery.endpointId()).orElse(null);
        if (endpoint == null || !endpoint.active()) {
            deliveries.recordAttempt(delivery.id(), "CANCELLED", clock.instant(), "Эндпоинт отключён", null);
            return;
        }

        String body = serialize(delivery.payload());
        long timestamp = clock.instant().getEpochSecond();
        String signature = signer.sign(endpoint.secret(), timestamp, body);

        try {
            HttpResponse<String> response = client.deliver(
                    URI.create(endpoint.url()),
                    signature,
                    delivery.eventType(),
                    delivery.id().toString(),
                    delivery.payload());

            if (response.getStatus().getCode() < 300) {
                deliveries.recordAttempt(delivery.id(), "DELIVERED", clock.instant(), null, clock.instant());
                return;
            }
            apply(delivery, endpoint, FailureAction.ofStatus(response.getStatus().getCode()),
                    "HTTP " + response.getStatus().getCode());
        } catch (HttpClientResponseException e) {
            apply(delivery, endpoint, FailureAction.of(e),
                    "HTTP %d: %s".formatted(e.getStatus().getCode(), e.getMessage()));
        } catch (RuntimeException e) {
            apply(delivery, endpoint, FailureAction.of(e),
                    e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    /**
     * Реакция на отказ зависит от его категории, а не от кода: без этой развилки
     * пять попыток тратятся на ошибку, которая не изменится никогда.
     */
    private void apply(WebhookDeliveryEntity delivery, WebhookEndpointEntity endpoint,
                       FailureAction action, String error) {
        switch (action) {
            case RETRY -> reschedule(delivery, error);
            case ABANDON -> {
                deliveries.recordAttempt(delivery.id(), "FAILED", clock.instant(), error, null);
                LOG.warn("Доставка {} отклонена получателем безвозвратно: {}", delivery.id(), error);
            }
            case DEACTIVATE -> {
                endpoints.deactivate(endpoint.id());
                deliveries.recordAttempt(delivery.id(), "CANCELLED", clock.instant(), error, null);
                LOG.warn("Эндпоинт {} отключён: получатель ответил 410 Gone", endpoint.id());
            }
        }
    }

    /**
     * Экспоненциальная задержка с потолком. Мгновенный повтор бесполезен:
     * если чужой сервис лежит, он лежит и через секунду.
     */
    private void reschedule(WebhookDeliveryEntity delivery, String error) {
        int attempts = delivery.attempts() + 1;
        if (attempts >= configuration.maxAttempts()) {
            deliveries.recordAttempt(delivery.id(), "FAILED", clock.instant(), error, null);
            LOG.warn("Доставка {} исчерпала попытки: {}", delivery.id(), error);
            return;
        }
        Duration backoff = Duration.ofMillis(Math.min(
                configuration.maxBackoff().toMillis(),
                (long) (configuration.initialBackoff().toMillis()
                        * Math.pow(configuration.backoffMultiplier(), attempts - 1))));

        Instant next = clock.instant().plus(backoff);
        deliveries.recordAttempt(delivery.id(), "PENDING", next, error, null);
        LOG.debug("Доставка {} отложена на {} после ошибки: {}", delivery.id(), backoff, error);
    }

    private String serialize(Map<String, Object> payload) {
        try {
            return new String(objectMapper.writeValueAsBytes(payload), java.nio.charset.StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("Не удалось сериализовать вебхук", e);
        }
    }
}
