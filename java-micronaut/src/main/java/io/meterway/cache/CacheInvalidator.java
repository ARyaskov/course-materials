package io.meterway.cache;

import io.micronaut.cache.CacheManager;
import io.micronaut.transaction.TransactionOperations;
import io.micronaut.transaction.support.TransactionSynchronization;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;

/**
 * Вытеснение записи кэша после коммита, а не внутри транзакции.
 * <p>
 * {@code @CacheInvalidate} на транзакционном методе срабатывает до коммита: между
 * вытеснением и коммитом другой поток успевает перечитать старое значение и закэшировать
 * его заново, а при откате запись вытесняется вообще без причины.
 * <p>
 * Вне транзакции вытеснение выполняется сразу — метод обязан работать в обоих случаях.
 */
@Singleton
public class CacheInvalidator {

    private static final Logger LOG = LoggerFactory.getLogger(CacheInvalidator.class);

    private final CacheManager<?> cacheManager;
    private final TransactionOperations<Connection> transactions;

    public CacheInvalidator(CacheManager<?> cacheManager,
                            TransactionOperations<Connection> transactions) {
        this.cacheManager = cacheManager;
        this.transactions = transactions;
    }

    public void invalidateAfterCommit(String cacheName, Object key) {
        transactions.findTransactionStatus().ifPresentOrElse(
                status -> status.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        invalidate(cacheName, key);
                    }
                }),
                () -> invalidate(cacheName, key));
    }

    private void invalidate(String cacheName, Object key) {
        cacheManager.getCache(cacheName).invalidate(key);
        LOG.debug("Запись {}:{} вытеснена", cacheName, key);
    }
}
