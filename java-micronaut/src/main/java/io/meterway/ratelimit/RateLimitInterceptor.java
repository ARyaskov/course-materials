package io.meterway.ratelimit;

import io.lettuce.core.RedisException;
import io.lettuce.core.api.StatefulRedisConnection;
import io.meterway.security.TenantContextElement;
import io.micrometer.core.instrument.MeterRegistry;
import io.micronaut.aop.InterceptorBean;
import io.micronaut.aop.MethodInterceptor;
import io.micronaut.aop.MethodInvocationContext;
import io.micronaut.core.order.Ordered;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Проверка лимита частоты обращений.
 * <p>
 * Порядок — самый внешний: отклонённый запрос не должен ни открывать транзакцию,
 * ни попадать в журнал аудита.
 * <p>
 * Пара INCR и EXPIRE выполняется без атомарности сознательно: гонка между ними даёт
 * ключ без TTL, что чинится следующим окном. Для квот потребления, где цена ошибки —
 * деньги, используется Lua-скрипт; для лимита частоты упрощение оправданно.
 * <p>
 * При недоступности Redis запрос пропускается: полный отказ API из-за неработающего
 * лимитера хуже временного отсутствия лимита. Счётчик degraded делает это заметным.
 */
@Singleton
@InterceptorBean(RateLimited.class)
public class RateLimitInterceptor implements MethodInterceptor<Object, Object>, Ordered {

    private static final Logger LOG = LoggerFactory.getLogger(RateLimitInterceptor.class);

    private final Map<String, RateLimitPolicy> policies;
    private final StatefulRedisConnection<String, String> redis;
    private final MeterRegistry registry;
    private final Clock clock;

    public RateLimitInterceptor(List<RateLimitPolicy> policies,
                                StatefulRedisConnection<String, String> redis,
                                MeterRegistry registry,
                                Clock clock) {
        this.policies = policies.stream()
                .collect(Collectors.toUnmodifiableMap(RateLimitPolicy::getName, Function.identity()));
        this.redis = redis;
        this.registry = registry;
        this.clock = clock;
    }

    @Override
    public Object intercept(MethodInvocationContext<Object, Object> context) {
        String name = context.stringValue(RateLimited.class).orElseThrow();
        RateLimitPolicy policy = policies.get(name);
        if (policy == null) {
            throw new IllegalStateException("Политика лимита не настроена: meterway.rate-limits." + name);
        }

        UUID tenantId = TenantContextElement.currentTenantId()
                .orElseThrow(() -> new IllegalStateException("Лимит требует контекста тенанта"));

        long windowSeconds = policy.getWindow().toSeconds();
        long epochSecond = clock.instant().getEpochSecond();
        long windowStart = epochSecond / windowSeconds;
        String key = "meterway:ratelimit:%s:%s:%d".formatted(name, tenantId, windowStart);

        long used = increment(key, policy, windowSeconds);
        if (used > policy.getLimit()) {
            registry.counter("meterway.ratelimit.rejected", "policy", name).increment();
            throw new RateLimitExceededException(name, policy.getLimit(),
                    windowSeconds - (epochSecond % windowSeconds));
        }
        return context.proceed();
    }

    private long increment(String key, RateLimitPolicy policy, long windowSeconds) {
        try {
            long value = redis.sync().incr(key);
            if (value == 1L) {
                redis.sync().expire(key, windowSeconds * 2);
            }
            return value;
        } catch (RedisException e) {
            registry.counter("meterway.ratelimit.degraded", "policy", policy.getName()).increment();
            LOG.warn("Redis недоступен, лимит {} не применён: {}", policy.getName(), e.getMessage());
            return 0L;
        }
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE + 5;
    }
}
