package io.meterway.quota;

import io.lettuce.core.RedisException;
import io.lettuce.core.ScriptOutputType;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import io.meterway.config.QuotaConfiguration;
import io.meterway.persistence.entity.QuotaPolicyEntity;
import io.meterway.persistence.repository.QuotaPolicyRepository;
import io.micronaut.cache.annotation.Cacheable;
import io.micronaut.core.io.ResourceResolver;
import jakarta.annotation.PostConstruct;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Проверка и списание квот в Redis.
 * <p>
 * Скрипт грузится один раз, дальше вызывается по SHA через EVALSHA: это экономит
 * пересылку тела скрипта на каждом обращении и не мешает Redis выкинуть скрипт из кэша —
 * Lettuce переотправит его при NOSCRIPT.
 */
@Singleton
public class QuotaService {

    private static final Logger LOG = LoggerFactory.getLogger(QuotaService.class);

    private final StatefulRedisConnection<String, String> connection;
    private final QuotaPolicyRepository policies;
    private final QuotaConfiguration configuration;
    private final ResourceResolver resources;
    private final Clock clock;

    private String consumeSha;
    private String releaseSha;

    public QuotaService(StatefulRedisConnection<String, String> connection,
                        QuotaPolicyRepository policies,
                        QuotaConfiguration configuration,
                        ResourceResolver resources,
                        Clock clock) {
        this.connection = connection;
        this.policies = policies;
        this.configuration = configuration;
        this.resources = resources;
        this.clock = clock;
    }

    @PostConstruct
    void loadScripts() {
        RedisCommands<String, String> commands = connection.sync();
        consumeSha = commands.scriptLoad(readScript("classpath:redis/quota-check-and-consume.lua"));
        releaseSha = commands.scriptLoad(readScript("classpath:redis/quota-release.lua"));
        LOG.info("Lua-скрипты квот загружены: consume={}, release={}", consumeSha, releaseSha);
    }

    /**
     * Проверяет и сразу списывает квоту. Возвращает первое запрещающее решение; если все
     * политики пропустили — самое строгое из разрешающих, то есть с наименьшим остатком.
     * <p>
     * Возвращать {@link QuotaDecision#unlimited} при успехе было бы проще, но тогда
     * контроллер не смог бы выставить заголовки {@code X-RateLimit-*}: у него не осталось бы
     * ни лимита, ни остатка, ни времени до сброса окна.
     */
    public QuotaDecision checkAndConsume(UUID tenantId, UUID customerId, String meterCode, BigDecimal quantity) {
        if (!configuration.enabled()) {
            return QuotaDecision.unlimited(meterCode);
        }
        List<QuotaPolicyEntity> applicable = applicablePolicies(tenantId, customerId, meterCode);
        if (applicable.isEmpty()) {
            return QuotaDecision.unlimited(meterCode);
        }

        long requested = quantity.setScale(0, RoundingMode.CEILING).longValueExact();
        Instant now = clock.instant();
        QuotaDecision tightest = null;

        for (QuotaPolicyEntity policy : applicable) {
            QuotaWindow window = QuotaWindow.parse(policy.windowSpec());
            String key = counterKey(tenantId, customerId, meterCode, window, now);
            QuotaDecision decision = evaluate(key, requested, policy.limitValue(), window, meterCode, now);
            if (!decision.allowed()) {
                return decision;
            }
            if (tightest == null || decision.remaining() < tightest.remaining()) {
                tightest = decision;
            }
        }
        return tightest;
    }

    /** Возврат списанного количества, если событие было отклонено после проверки квоты. */
    public void release(UUID tenantId, UUID customerId, String meterCode, BigDecimal quantity) {
        if (!configuration.enabled()) {
            return;
        }
        long amount = quantity.setScale(0, RoundingMode.CEILING).longValueExact();
        Instant now = clock.instant();
        for (QuotaPolicyEntity policy : applicablePolicies(tenantId, customerId, meterCode)) {
            QuotaWindow window = QuotaWindow.parse(policy.windowSpec());
            String key = counterKey(tenantId, customerId, meterCode, window, now);
            try {
                connection.sync().evalsha(releaseSha, ScriptOutputType.INTEGER, new String[]{key},
                        Long.toString(amount));
            } catch (RedisException e) {
                LOG.warn("Не удалось вернуть квоту по ключу {}: {}", key, e.getMessage());
            }
        }
    }

    private QuotaDecision evaluate(String key, long requested, long limit,
                                   QuotaWindow window, String meterCode, Instant now) {
        try {
            List<Long> result = connection.sync().evalsha(
                    consumeSha,
                    ScriptOutputType.MULTI,
                    new String[]{key},
                    Long.toString(requested),
                    Long.toString(limit),
                    Long.toString(window.keyTtl().toSeconds()));

            boolean allowed = result.get(0) == 1L;
            long used = result.get(1);
            // Время до сброса считается по окну, а не берётся из TTL ключа: TTL намеренно
            // вдвое больше окна (запас на перекос часов), и в Retry-After он дал бы клиенту
            // указание ждать вдвое дольше, чем нужно.
            return new QuotaDecision(allowed, meterCode, limit, used, window.secondsUntilReset(now));
        } catch (RedisException e) {
            LOG.error("Redis недоступен при проверке квоты {}: {}", key, e.getMessage());
            if (configuration.failOpen()) {
                return QuotaDecision.unlimited(meterCode);
            }
            return new QuotaDecision(false, meterCode, limit, limit, window.secondsUntilReset(now));
        }
    }

    /**
     * Политики меняются редко, а читаются на каждом событии.
     * Кэш здесь снимает основную нагрузку с PostgreSQL на пути ingest.
     */
    @Cacheable(value = "quota-policies", parameters = {"tenantId", "customerId", "meterCode"})
    protected List<QuotaPolicyEntity> applicablePolicies(UUID tenantId, UUID customerId, String meterCode) {
        return policies.findApplicable(tenantId, customerId, meterCode);
    }

    String counterKey(UUID tenantId, UUID customerId, String meterCode, QuotaWindow window, Instant now) {
        return "%s:%s:%s:%s:%s:%d".formatted(
                configuration.keyPrefix(), tenantId, customerId, meterCode,
                window.name(), window.windowStart(now).getEpochSecond());
    }

    private String readScript(String location) {
        try (InputStream stream = resources.getResourceAsStream(location)
                .orElseThrow(() -> new IllegalStateException("Скрипт не найден: " + location))) {
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException("Не удалось прочитать " + location, e);
        }
    }
}
