package io.meterway.quota;

import io.meterway.persistence.entity.CustomerEntity;
import io.meterway.persistence.entity.QuotaPolicyEntity;
import io.meterway.persistence.entity.TenantEntity;
import io.meterway.persistence.repository.CustomerRepository;
import io.meterway.persistence.repository.QuotaPolicyRepository;
import io.meterway.persistence.repository.TenantRepository;
import io.micronaut.cache.CacheManager;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Проверка того, ради чего в квотах появился Lua-скрипт.
 * <p>
 * Последовательный тест проходит и с реализацией из трёх команд: гонка между
 * {@code GET} и {@code INCRBY} проявляется только при одновременных обращениях.
 */
@MicronautTest(transactional = false)
class QuotaConcurrencyTest {

    private static final int LIMIT = 100;
    private static final String METER = "api.requests";

    @Inject
    QuotaService quotas;

    @Inject
    TenantRepository tenants;

    @Inject
    CustomerRepository customers;

    @Inject
    QuotaPolicyRepository policies;

    @Inject
    CacheManager<?> cacheManager;

    private UUID tenantId;
    private UUID customerId;

    @BeforeEach
    void seed() {
        tenantId = UUID.randomUUID();
        tenants.save(TenantEntity.create(tenantId, "Quota tenant"));
        customerId = customers.save(
                CustomerEntity.create(tenantId, "ref-" + tenantId, "Quota customer", "EUR")).id();

        policies.save(new QuotaPolicyEntity(
                UUID.randomUUID(), tenantId, customerId, METER, "HOUR", LIMIT, "REJECT", true, null));

        // Политики кэшируются на минуту: без сброса тест увидел бы пустой список от соседнего теста.
        cacheManager.getCache("quota-policies").invalidateAll();
    }

    @Test
    @DisplayName("Под конкуренцией разрешено ровно столько, сколько допускает лимит")
    void limitHoldsUnderConcurrency() throws Exception {
        int threads = 32;
        int attemptsPerThread = 10;

        AtomicInteger allowed = new AtomicInteger();
        CountDownLatch start = new CountDownLatch(1);

        try (ExecutorService pool = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < threads; i++) {
                pool.submit(() -> {
                    start.await();
                    for (int j = 0; j < attemptsPerThread; j++) {
                        if (quotas.checkAndConsume(tenantId, customerId, METER, BigDecimal.ONE).allowed()) {
                            allowed.incrementAndGet();
                        }
                    }
                    return null;
                });
            }
            start.countDown();
        }

        assertEquals(LIMIT, allowed.get(),
                "проверка и списание обязаны выполняться одной операцией на стороне Redis");
    }

    @Test
    @DisplayName("Решение несёт остаток и время до сброса окна")
    void decisionCarriesRemainingAndReset() {
        QuotaDecision first = quotas.checkAndConsume(tenantId, customerId, METER, BigDecimal.valueOf(40));

        assertTrue(first.allowed());
        assertEquals(LIMIT, first.limit());
        assertEquals(LIMIT - 40, first.remaining());
        assertTrue(first.resetInSeconds() > 0 && first.resetInSeconds() <= 3600);

        QuotaDecision blocked = quotas.checkAndConsume(tenantId, customerId, METER, BigDecimal.valueOf(80));

        assertFalse(blocked.allowed());
        assertEquals(40L, blocked.used(), "отклонённое списание не увеличивает счётчик");
    }

    @Test
    @DisplayName("Возврат квоты уменьшает счётчик")
    void releaseReturnsQuota() {
        quotas.checkAndConsume(tenantId, customerId, METER, BigDecimal.valueOf(60));
        quotas.release(tenantId, customerId, METER, BigDecimal.valueOf(60));

        QuotaDecision after = quotas.checkAndConsume(tenantId, customerId, METER, BigDecimal.valueOf(100));

        assertTrue(after.allowed(), "после возврата всё окно снова доступно");
    }
}
