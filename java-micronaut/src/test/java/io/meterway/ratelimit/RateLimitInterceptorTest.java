package io.meterway.ratelimit;

import io.lettuce.core.api.StatefulRedisConnection;
import io.meterway.security.TenantContextElement;
import io.micronaut.core.propagation.PropagatedContext;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;
import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Второй тест важнее первого: лимит, ключ которого не содержит тенанта,
 * позволил бы одному клиенту исчерпать лимит всех остальных.
 */
@MicronautTest(startApplication = false)
@io.micronaut.context.annotation.Property(name = "meterway.rate-limits.reports.limit", value = "5")
class RateLimitInterceptorTest {

    @Singleton
    static class Probe {

        // Политика «reports» объявлена в application.properties: стартовая проверка
        // RateLimitConfigurationAudit обходит все бины, включая тестовые,
        // и незнакомое имя политики уронило бы любой контекст.
        @RateLimited("reports")
        String work() {
            return "ok";
        }
    }

    @Inject Probe probe;
    @Inject StatefulRedisConnection<String, String> redis;

    @BeforeEach
    void clearCounters() {
        redis.sync().flushdb();
    }

    private <T> T withTenant(UUID tenantId, Supplier<T> action) {
        return PropagatedContext.getOrEmpty()
                .plus(new TenantContextElement(tenantId, "test"))
                .propagate(action);
    }

    @Test
    @DisplayName("Запросы сверх лимита отклоняются, в пределах лимита проходят")
    void enforcesLimit() {
        UUID tenantId = UUID.randomUUID();

        withTenant(tenantId, () -> {
            for (int i = 0; i < 5; i++) {
                assertEquals("ok", probe.work());
            }
            RateLimitExceededException error =
                    assertThrows(RateLimitExceededException.class, probe::work);
            assertEquals(5, error.limit());
            assertTrue(error.retryAfterSeconds() > 0);
            return null;
        });
    }

    @Test
    @DisplayName("Лимит считается отдельно для каждого тенанта")
    void isolatesTenants() {
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();

        withTenant(first, () -> {
            for (int i = 0; i < 5; i++) {
                probe.work();
            }
            assertThrows(RateLimitExceededException.class, probe::work);
            return null;
        });

        withTenant(second, () -> {
            assertEquals("ok", probe.work(), "лимит первого тенанта не должен влиять на второго");
            return null;
        });
    }
}
