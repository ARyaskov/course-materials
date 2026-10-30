package io.meterway.realtime;

import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.repository.TenantRepository;
import io.micronaut.context.annotation.Property;
import io.micronaut.http.HttpRequest;
import io.micronaut.websocket.exceptions.WebSocketClientException;
import io.micronaut.security.authentication.UsernamePasswordCredentials;
import io.micronaut.security.token.render.BearerAccessRefreshToken;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import io.micronaut.websocket.WebSocketClient;
import io.micronaut.http.client.HttpClient;
import io.micronaut.http.client.annotation.Client;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Живой поток: рассылка по тенанту и запрет на чужой поток.
 * <p>
 * Пара тестов проверяет две разные границы — подключение и рассылку. Ошибка в любой
 * даёт утечку данных между тенантами, и одного теста недостаточно.
 */
@MicronautTest(transactional = false)
@Property(name = "meterway.console.users.viewer-a.password-hash",
        value = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
@Property(name = "meterway.console.users.viewer-a.tenant-id",
        value = "00000000-0000-0000-0000-0000000000c1")
@Property(name = "meterway.console.users.viewer-a.roles[0]", value = "CONSOLE")
@Property(name = "meterway.console.users.viewer-b.password-hash",
        value = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
@Property(name = "meterway.console.users.viewer-b.tenant-id",
        value = "00000000-0000-0000-0000-0000000000d1")
@Property(name = "meterway.console.users.viewer-b.roles[0]", value = "CONSOLE")
class UsageStreamSocketTest {

    private static final UUID TENANT_A = UUID.fromString("00000000-0000-0000-0000-0000000000c1");
    private static final UUID TENANT_B = UUID.fromString("00000000-0000-0000-0000-0000000000d1");

    @Inject
    @Client("/")
    HttpClient httpClient;

    @Inject
    @Client("/")
    WebSocketClient webSocketClient;

    @Inject
    UsageStreamSocket socket;

    @Inject
    TenantRepository tenants;

    private String tokenA;
    private String tokenB;

    @BeforeEach
    void seed() {
        if (tenants.findById(TENANT_A).isEmpty()) {
            tenants.save(TenantEntity.create(TENANT_A, "Stream tenant A"));
        }
        if (tenants.findById(TENANT_B).isEmpty()) {
            tenants.save(TenantEntity.create(TENANT_B, "Stream tenant B"));
        }
        tokenA = login("viewer-a");
        tokenB = login("viewer-b");
    }

    private String login(String username) {
        return httpClient.toBlocking().retrieve(
                HttpRequest.POST("/login", new UsernamePasswordCredentials(username, "test")),
                BearerAccessRefreshToken.class).getAccessToken();
    }

    private UsageStreamClient connect(UUID tenantId, String token) {
        return Mono.from(webSocketClient.connect(UsageStreamClient.class,
                HttpRequest.GET("/v1/stream/usage/" + tenantId).bearerAuth(token))).block();
    }

    @Test
    @DisplayName("Обновление доходит до своего тенанта и не доходит до чужого")
    void broadcastsToOwnTenantOnly() throws Exception {
        try (UsageStreamClient a = connect(TENANT_A, tokenA);
             UsageStreamClient b = connect(TENANT_B, tokenB)) {

            socket.publish(TENANT_A.toString(), new UsageUpdate(
                    UUID.randomUUID(), "api.requests", BigDecimal.valueOf(42), 3L, Instant.now()));

            Instant deadline = Instant.now().plus(Duration.ofSeconds(5));
            while (a.received().isEmpty() && Instant.now().isBefore(deadline)) {
                Thread.sleep(50);
            }

            assertEquals(1, a.received().size(), "свой тенант должен получить обновление");
            assertEquals(0, a.received().getFirst().value().compareTo(BigDecimal.valueOf(42)));
            assertTrue(b.received().isEmpty(), "чужой тенант не должен получать обновления");
        }
    }

    @Test
    @DisplayName("Оператор не подключится к потоку чужого тенанта")
    void rejectsForeignTenant() throws Exception {
        // Отказ происходит в @OnOpen, то есть уже после успешного рукопожатия:
        // сервер закрывает соединение кодом POLICY_VIOLATION, а не отвечает 403.
        try (UsageStreamClient foreign = connect(TENANT_B, tokenA)) {
            Instant deadline = Instant.now().plus(Duration.ofSeconds(5));
            while (foreign.isOpen() && Instant.now().isBefore(deadline)) {
                Thread.sleep(50);
            }
            assertFalse(foreign.isOpen(), "соединение к чужому тенанту должно быть закрыто сервером");
        }
    }

    @Test
    @DisplayName("Без токена соединение не устанавливается")
    void rejectsAnonymous() {
        // Отказ на рукопожатии приходит как WebSocketClientException, а не как
        // HttpClientResponseException: код 401 отдаётся до апгрейда протокола,
        // и клиент видит его как неудавшееся рукопожатие.
        WebSocketClientException error = assertThrows(WebSocketClientException.class,
                () -> Mono.from(webSocketClient.connect(
                        UsageStreamClient.class, "/v1/stream/usage/" + TENANT_A)).block());

        assertTrue(error.getMessage().contains("handshake"), error.getMessage());
    }
}
