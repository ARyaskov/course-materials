package io.meterway.quota;

import io.lettuce.core.RedisException;
import io.lettuce.core.ScriptOutputType;
import io.lettuce.core.SetArgs;
import io.lettuce.core.api.StatefulRedisConnection;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * Распределённая блокировка на Redis.
 * <p>
 * {@code SET key value NX PX ttl} захватывает, скрипт сравнения владельца — освобождает.
 * Без сравнения владельца задача, задержавшаяся дольше TTL, снимет чужую блокировку.
 * <p>
 * Блокировка здесь — оптимизация, а не гарантия корректности: закрытие периода
 * остаётся идемпотентным и без неё.
 */
@Singleton
public class DistributedLock {

    private static final Logger LOG = LoggerFactory.getLogger(DistributedLock.class);

    private static final String RELEASE_SCRIPT = """
            if redis.call('GET', KEYS[1]) == ARGV[1] then
                return redis.call('DEL', KEYS[1])
            end
            return 0
            """;

    private final StatefulRedisConnection<String, String> connection;

    public DistributedLock(StatefulRedisConnection<String, String> connection) {
        this.connection = connection;
    }

    public Optional<String> tryAcquire(String key, Duration ttl) {
        String token = UUID.randomUUID().toString();
        try {
            String result = connection.sync().set(key, token, SetArgs.Builder.nx().px(ttl));
            return "OK".equals(result) ? Optional.of(token) : Optional.empty();
        } catch (RedisException e) {
            LOG.warn("Не удалось захватить блокировку {}: {}", key, e.getMessage());
            return Optional.empty();
        }
    }

    public void release(String key, String token) {
        try {
            connection.sync().eval(RELEASE_SCRIPT, ScriptOutputType.INTEGER, new String[]{key}, token);
        } catch (RedisException e) {
            LOG.warn("Не удалось освободить блокировку {}: {}", key, e.getMessage());
        }
    }

    /** Выполняет действие под блокировкой; если захватить не удалось — возвращает пустой Optional. */
    public <T> Optional<T> withLock(String key, Duration ttl, Supplier<T> action) {
        Optional<String> token = tryAcquire(key, ttl);
        if (token.isEmpty()) {
            return Optional.empty();
        }
        try {
            return Optional.ofNullable(action.get());
        } finally {
            release(key, token.get());
        }
    }
}
