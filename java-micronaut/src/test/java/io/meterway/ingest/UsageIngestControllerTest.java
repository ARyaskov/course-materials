package io.meterway.ingest;

import io.meterway.persistence.entity.ApiKeyEntity;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.repository.ApiKeyRepository;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.meterway.security.ApiKeyHasher;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.annotation.Client;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Интеграционный тест приёма. PostgreSQL и Redis поднимает Micronaut Test Resources:
 * в тесте нет ни одной строки про контейнеры, а адреса подставляются автоматически.
 */
@MicronautTest(transactional = false)
class UsageIngestControllerTest {

    private static final UUID TENANT = UUID.fromString("00000000-0000-0000-0000-00000000f001");
    private static final String CUSTOMER_REF = "cust-integration";

    @Inject
    @Client("/")
    HttpClient client;

    @Inject
    TenantRepository tenants;

    @Inject
    CustomerRepository customers;

    @Inject
    ApiKeyRepository apiKeys;

    @Inject
    ApiKeyHasher hasher;

    private String presentedKey;

    @BeforeEach
    void seed() {
        if (tenants.findById(TENANT).isEmpty()) {
            tenants.save(TenantEntity.create(TENANT, "Integration tenant"));
        }
        if (customers.findByTenantIdAndExternalRef(TENANT, CUSTOMER_REF).isEmpty()) {
            customers.save(CustomerEntity.create(TENANT, CUSTOMER_REF, "Integration customer", "EUR"));
        }
        ApiKeyHasher.GeneratedKey generated = hasher.generate("test");
        apiKeys.save(new ApiKeyEntity(
                UUID.randomUUID(), TENANT, generated.prefix(), generated.secretHash(),
                "integration", new String[]{"INGEST"}, null, null));
        presentedKey = generated.presented();
    }

    private UsageEventRequest event(String key, BigDecimal quantity) {
        return new UsageEventRequest(key, "api.requests", CUSTOMER_REF,
                Instant.now().minusSeconds(60), quantity, Map.of("endpoint", "/v1/items"));
    }

    private HttpRequest<UsageEventRequest> post(UsageEventRequest body) {
        return HttpRequest.POST("/v1/usage-events", body).header("X-Api-Key", presentedKey);
    }

    @Test
    @DisplayName("Первое событие принимается с кодом 202")
    void acceptsFirstEvent() {
        var response = client.toBlocking().exchange(
                post(event("it-" + UUID.randomUUID(), BigDecimal.ONE)), IngestOutcome.class);

        assertEquals(HttpStatus.ACCEPTED, response.getStatus());
        IngestOutcome outcome = response.body();
        assertNotNull(outcome);
        assertInstanceOf(IngestOutcome.Accepted.class, outcome);
    }

    @Test
    @DisplayName("Повтор с тем же ключом и телом распознаётся как дубликат, а не как новое событие")
    void detectsDuplicate() {
        // Тело должно быть побайтово тем же: отпечаток считается в том числе по occurredAt,
        // и пересоздание запроса с Instant.now() дало бы конфликт вместо дубликата.
        UsageEventRequest request = event("it-dup-" + UUID.randomUUID(), BigDecimal.ONE);

        client.toBlocking().exchange(post(request), IngestOutcome.class);
        var second = client.toBlocking().exchange(post(request), IngestOutcome.class);

        assertEquals(HttpStatus.OK, second.getStatus());
        assertInstanceOf(IngestOutcome.Duplicate.class, second.body());
    }

    @Test
    @DisplayName("Тот же ключ с другим количеством — конфликт 409")
    void detectsKeyReuse() {
        String key = "it-conflict-" + UUID.randomUUID();
        UsageEventRequest first = event(key, BigDecimal.ONE);
        client.toBlocking().exchange(post(first), IngestOutcome.class);

        UsageEventRequest changed = new UsageEventRequest(key, first.meterCode(), first.customerRef(),
                first.occurredAt(), BigDecimal.TEN, first.properties());

        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(post(changed), IngestOutcome.class));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
    }

    @Test
    @DisplayName("Без ключа доступа ingest отвечает 401")
    void rejectsAnonymous() {
        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(
                        HttpRequest.POST("/v1/usage-events", event("it-anon", BigDecimal.ONE)),
                        IngestOutcome.class));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
    }

    @Test
    @DisplayName("Неизвестная метрика отклоняется с кодом 400 и понятной причиной")
    void rejectsUnknownMeter() {
        UsageEventRequest request = new UsageEventRequest(
                "it-meter-" + UUID.randomUUID(), "api.unknown", CUSTOMER_REF,
                Instant.now().minusSeconds(60), BigDecimal.ONE, Map.of());

        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(post(request), IngestOutcome.class));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
    }
}
