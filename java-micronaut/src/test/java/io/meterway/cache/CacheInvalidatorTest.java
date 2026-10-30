package io.meterway.cache;

import io.micronaut.cache.CacheManager;
import io.micronaut.cache.SyncCache;
import io.micronaut.core.type.Argument;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Вытеснение после коммита: внутри транзакции запись обязана оставаться на месте,
 * а откат не должен вытеснять её вовсе.
 */
@MicronautTest(transactional = false)
class CacheInvalidatorTest {

    private static final String CACHE = "customers";
    private static final String KEY = "invalidator-test";

    @Inject
    CacheManager<?> cacheManager;

    @Inject
    Probe probe;

    private SyncCache<?> cache;

    @BeforeEach
    void seed() {
        cache = cacheManager.getCache(CACHE);
        cache.put(KEY, "value");
    }

    private boolean cached() {
        return cache.get(KEY, Argument.STRING).isPresent();
    }

    @Test
    @DisplayName("Внутри транзакции запись ещё на месте, после коммита — нет")
    void invalidatesAfterCommit() {
        probe.commitAndCheck(() -> assertTrue(cached(), "до коммита запись обязана оставаться"));

        assertTrue(cache.get(KEY, Argument.STRING).isEmpty(), "после коммита запись вытеснена");
    }

    @Test
    @DisplayName("Откат не вытесняет запись")
    void keepsEntryOnRollback() {
        assertThrows(IllegalStateException.class, probe::rollback);

        assertTrue(cached(), "откат не должен вытеснять запись");
    }

    @Test
    @DisplayName("Вне транзакции вытеснение выполняется сразу")
    void invalidatesImmediatelyOutsideTransaction() {
        probe.invalidator().invalidateAfterCommit(CACHE, KEY);

        assertTrue(cache.get(KEY, Argument.STRING).isEmpty());
    }

    @Singleton
    static class Probe {

        private final CacheInvalidator invalidator;

        Probe(CacheInvalidator invalidator) {
            this.invalidator = invalidator;
        }

        CacheInvalidator invalidator() {
            return invalidator;
        }

        @Transactional
        void commitAndCheck(Runnable assertionInsideTransaction) {
            invalidator.invalidateAfterCommit(CACHE, KEY);
            assertionInsideTransaction.run();
        }

        @Transactional
        void rollback() {
            invalidator.invalidateAfterCommit(CACHE, KEY);
            throw new IllegalStateException("откат");
        }
    }
}
