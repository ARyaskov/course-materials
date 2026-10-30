package io.meterway.security;

import io.meterway.domain.BillingPeriod;
import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.InvoiceEntity;
import io.meterway.persistence.entity.PlanEntity;
import io.meterway.persistence.entity.SubscriptionEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.InvoiceRepository;
import io.meterway.persistence.repository.PlanRepository;
import io.meterway.persistence.repository.SubscriptionRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.micronaut.context.annotation.Property;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.MediaType;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.annotation.Client;
import io.micronaut.http.client.exceptions.HttpClientResponseException;
import io.micronaut.security.authentication.UsernamePasswordCredentials;
import io.micronaut.security.token.render.BearerAccessRefreshToken;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Матрица авторизации панели: 200, 401, 403 и изоляция данных между тенантами.
 * <p>
 * Пароль обоих операторов — {@code test}: в конфигурации лежит его SHA-256,
 * тот же алгоритм, что у {@link ApiKeyHasher}.
 */
@MicronautTest(transactional = false)
@Property(name = "meterway.console.users.viewer.password-hash",
        value = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
@Property(name = "meterway.console.users.viewer.tenant-id",
        value = "00000000-0000-0000-0000-0000000000a1")
@Property(name = "meterway.console.users.viewer.roles[0]", value = "CONSOLE")
@Property(name = "meterway.console.users.owner.password-hash",
        value = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
@Property(name = "meterway.console.users.owner.tenant-id",
        value = "00000000-0000-0000-0000-0000000000b1")
@Property(name = "meterway.console.users.owner.roles[0]", value = "CONSOLE")
@Property(name = "meterway.console.users.owner.roles[1]", value = "ADMIN")
class SecurityMatrixTest {

    private static final UUID TENANT_A = UUID.fromString("00000000-0000-0000-0000-0000000000a1");
    private static final UUID TENANT_B = UUID.fromString("00000000-0000-0000-0000-0000000000b1");
    private static final YearMonth PERIOD = YearMonth.of(2026, 4);

    @Inject
    @Client("/")
    HttpClient client;

    @Inject
    TenantRepository tenants;

    @Inject
    CustomerRepository customers;

    @Inject
    PlanRepository plans;

    @Inject
    SubscriptionRepository subscriptions;

    @Inject
    InvoiceRepository invoices;

    private String viewerToken;
    private String ownerToken;
    private UUID foreignInvoiceId;

    @BeforeEach
    void seed() {
        if (tenants.findById(TENANT_A).isEmpty()) {
            tenants.save(TenantEntity.create(TENANT_A, "Tenant A"));
        }
        if (tenants.findById(TENANT_B).isEmpty()) {
            tenants.save(TenantEntity.create(TENANT_B, "Tenant B"));
        }
        viewerToken = login("viewer");
        ownerToken = login("owner");
        foreignInvoiceId = invoiceOf(TENANT_B);
    }

    /** Счёт тенанта B: его увидит владелец и не увидит оператор тенанта A. */
    private UUID invoiceOf(UUID tenantId) {
        BillingPeriod period = BillingPeriod.ofMonth(PERIOD);
        CustomerEntity customer = customers.save(
                CustomerEntity.create(tenantId, "ref-" + UUID.randomUUID(), "Isolation customer", "EUR"));
        PlanEntity plan = plans.save(new PlanEntity(
                UUID.randomUUID(), tenantId, "plan-" + UUID.randomUUID(), "Isolation plan",
                "EUR", 0L, true, null));
        SubscriptionEntity subscription = subscriptions.save(new SubscriptionEntity(
                UUID.randomUUID(), tenantId, customer.id(), plan.id(), period.start(), null, null, null));

        return invoices.save(new InvoiceEntity(
                UUID.randomUUID(), tenantId, customer.id(), subscription.id(),
                period.start(), period.end(), "EUR", 12_300L, "ISSUED",
                Instant.now(), null, null)).id();
    }

    private String login(String username) {
        BearerAccessRefreshToken token = client.toBlocking().retrieve(
                HttpRequest.POST("/login", new UsernamePasswordCredentials(username, "test")),
                BearerAccessRefreshToken.class);
        return token.getAccessToken();
    }

    @Test
    @DisplayName("200: оператор со своей ролью читает отчёт своего тенанта")
    void allowsConsoleRole() {
        String body = client.toBlocking().retrieve(
                HttpRequest.GET("/v1/reports/usage?period=" + PERIOD).bearerAuth(viewerToken),
                String.class);

        assertEquals("[]", body);
    }

    @Test
    @DisplayName("401: без токена и в формате problem+json")
    void rejectsAnonymous() {
        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(
                        HttpRequest.GET("/v1/reports/usage?period=" + PERIOD)));

        assertEquals(HttpStatus.UNAUTHORIZED, error.getStatus());
        assertEquals(MediaType.APPLICATION_JSON_PROBLEM,
                error.getResponse().getContentType().orElseThrow().toString());

        // Тело не должно содержать внутренностей: org.zalando.problem.Problem наследует
        // Exception, и его прямая сериализация вынесла бы наружу стектрейс с именами
        // классов, файлов и номерами строк.
        String body = error.getResponse().getBody(String.class).orElse("");
        assertFalse(body.contains("stackTrace"), body);
        assertFalse(body.contains("io.micronaut"), body);
        assertTrue(body.contains("\"status\":401"), body);
    }

    /**
     * Путь именно тот, что объявлен контроллером: {@code /v1/billing}, а не {@code /v1/admin}.
     * <p>
     * Несуществующий маршрут при включённой безопасности тоже даёт 403 — аутентификация
     * прошла, правило не нашлось, действует запрет по умолчанию. Тест с опечаткой в пути
     * прошёл бы, ничего не проверив: он бы фиксировал отсутствие маршрута,
     * а не работу {@code @Secured("ADMIN")}.
     */
    @Test
    @DisplayName("403: роли CONSOLE недостаточно для закрытия периода")
    void rejectsInsufficientRole() {
        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(
                        HttpRequest.POST("/v1/billing/periods/" + PERIOD + "/close", null)
                                .bearerAuth(viewerToken)));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
    }

    @Test
    @DisplayName("200: роль ADMIN закрывает период по тому же пути")
    void allowsAdminRole() {
        HttpStatus status = client.toBlocking().exchange(
                        HttpRequest.POST("/v1/billing/periods/" + PERIOD + "/close", null)
                                .bearerAuth(ownerToken))
                .getStatus();

        assertEquals(HttpStatus.OK, status,
                "парный тест: без него 403 выше мог бы означать отсутствие маршрута");
    }

    @Test
    @DisplayName("404: счёт другого тенанта не находится, а не запрещается")
    void hidesForeignInvoice() {
        HttpClientResponseException error = assertThrows(HttpClientResponseException.class,
                () -> client.toBlocking().exchange(
                        HttpRequest.GET("/v1/reports/invoices/" + foreignInvoiceId)
                                .accept(MediaType.APPLICATION_JSON)   // у ресурса два представления
                                .bearerAuth(viewerToken)));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
    }

    @Test
    @DisplayName("Тот же счёт виден владельцу: 404 выше — изоляция, а не отсутствие данных")
    void ownerSeesOwnInvoice() {
        HttpStatus status = client.toBlocking().exchange(
                HttpRequest.GET("/v1/reports/invoices/" + foreignInvoiceId)
                        .accept(MediaType.APPLICATION_JSON)
                        .bearerAuth(ownerToken))
                .getStatus();

        assertEquals(HttpStatus.OK, status);
    }

    @Test
    @DisplayName("Токен несёт tenantId: без него запрос к отчётам не прошёл бы")
    void tokenCarriesTenant() {
        assertTrue(viewerToken.split("\\.").length == 3);

        String payload = new String(java.util.Base64.getUrlDecoder()
                .decode(viewerToken.split("\\.")[1]), java.nio.charset.StandardCharsets.UTF_8);

        assertTrue(payload.contains(TENANT_A.toString()), payload);
        assertTrue(payload.contains("CONSOLE"), payload);
    }
}
