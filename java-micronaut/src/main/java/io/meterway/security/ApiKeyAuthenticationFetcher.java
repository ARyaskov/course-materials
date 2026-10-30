package io.meterway.security;

import io.meterway.persistence.entity.ApiKeyEntity;
import io.meterway.persistence.repository.ApiKeyRepository;
import io.micronaut.cache.annotation.Cacheable;
import io.micronaut.http.HttpRequest;
import io.micronaut.scheduling.TaskExecutors;
import io.micronaut.scheduling.annotation.ExecuteOn;
import io.micronaut.security.authentication.Authentication;
import io.micronaut.security.filters.AuthenticationFetcher;
import jakarta.inject.Singleton;
import org.reactivestreams.Publisher;
import reactor.core.publisher.Mono;

import java.util.Map;
import java.util.Optional;

/**
 * Аутентификация ingest-эндпоинта по заголовку {@code X-Api-Key}.
 * <p>
 * {@link AuthenticationFetcher} — точка расширения Micronaut Security для схем,
 * которые не укладываются в пару «логин + пароль»: фетчер вызывается на каждом запросе
 * и возвращает готовый {@link Authentication} без прохода через AuthenticationProvider.
 */
@Singleton
public class ApiKeyAuthenticationFetcher implements AuthenticationFetcher<HttpRequest<?>> {

    public static final String HEADER = "X-Api-Key";

    private final ApiKeyRepository repository;
    private final ApiKeyHasher hasher;

    public ApiKeyAuthenticationFetcher(ApiKeyRepository repository, ApiKeyHasher hasher) {
        this.repository = repository;
        this.hasher = hasher;
    }

    @Override
    public Publisher<Authentication> fetchAuthentication(HttpRequest<?> request) {
        String presented = request.getHeaders().get(HEADER);
        if (presented == null || presented.isBlank()) {
            return Mono.empty();
        }
        String[] parts = hasher.split(presented);
        if (parts == null) {
            return Mono.empty();
        }
        return Mono.fromCallable(() -> authenticate(parts[0], parts[1]))
                .subscribeOn(reactor.core.scheduler.Schedulers.boundedElastic())
                .flatMap(Mono::justOrEmpty);
    }

    @ExecuteOn(TaskExecutors.BLOCKING)
    protected Optional<Authentication> authenticate(String prefix, String secret) {
        return lookup(prefix)
                .filter(ApiKeyEntity::isActive)
                .filter(key -> hasher.matches(secret, key.secretHash()))
                .map(key -> Authentication.build(
                        key.keyPrefix(),
                        java.util.List.of("INGEST"),
                        Map.of(
                                MeterwayPrincipal.TENANT_ATTRIBUTE, key.tenantId().toString(),
                                MeterwayPrincipal.KEY_ID_ATTRIBUTE, key.id().toString(),
                                "label", key.label()
                        )));
    }

    /**
     * Проверка ключа стоит одного обращения к базе на запрос — при частоте ingest это заметно.
     * Кэш живёт секунды: отозванный ключ перестаёт работать почти сразу.
     */
    @Cacheable(value = "api-keys", parameters = "prefix")
    protected Optional<ApiKeyEntity> lookup(String prefix) {
        return repository.findByKeyPrefixAndRevokedAtIsNull(prefix);
    }
}
