package beacon.security;

import beacon.config.BeaconSettings;
import beacon.domain.ApiKey;
import beacon.repository.ApiKeyRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.cache.AsyncCacheApi;
import play.cache.NamedCache;
import play.mvc.Http;

/**
 * Проверка ключей API.
 *
 * <p>Формат ключа: {@code <prefix>.<secret>}. В базе лежит префикс (по нему ищем)
 * и хеш секрета (его сверяем). Результат проверки кладётся в кэш на
 * {@code beacon.security.api-key-cache}: иначе каждый запрос к API стоил бы похода в БД.
 */
@Singleton
public class ApiKeyService {

    public record AuthenticatedOrg(String slug, long apiKeyId) {}

    private final ApiKeyRepository keys;
    private final PasswordHasher hasher;
    private final AsyncCacheApi cache;
    private final BeaconSettings settings;

    @Inject
    public ApiKeyService(
            ApiKeyRepository keys,
            PasswordHasher hasher,
            @NamedCache("api-key-cache") AsyncCacheApi cache,
            BeaconSettings settings) {
        this.keys = keys;
        this.hasher = hasher;
        this.cache = cache;
        this.settings = settings;
    }

    public CompletionStage<Optional<AuthenticatedOrg>> authenticate(Http.RequestHeader request) {
        Optional<String> raw = bearerToken(request);
        if (raw.isEmpty()) {
            return CompletableFuture.completedFuture(Optional.empty());
        }
        String token = raw.get();
        int dot = token.indexOf('.');
        if (dot <= 0 || dot == token.length() - 1) {
            return CompletableFuture.completedFuture(Optional.empty());
        }
        String prefix = token.substring(0, dot);
        String secret = token.substring(dot + 1);

        int ttl = (int) Math.max(1, settings.security().apiKeyCache().toSeconds());
        return cache.getOrElseUpdate("apikey:" + prefix, () -> keys.findByPrefix(prefix), ttl)
                .thenCompose(found -> verify(found, secret));
    }

    private CompletionStage<Optional<AuthenticatedOrg>> verify(Optional<ApiKey> found, String secret) {
        if (found.isEmpty() || !found.get().isActive()
                || !hasher.verifyApiSecret(secret, found.get().secretHash())) {
            return CompletableFuture.completedFuture(Optional.empty());
        }
        ApiKey key = found.get();
        return keys.orgSlugOf(key.id()).thenApply(slug -> {
            keys.touch(key.id(), Instant.now());
            return slug == null ? Optional.<AuthenticatedOrg>empty()
                    : Optional.of(new AuthenticatedOrg(slug, key.id()));
        });
    }

    private static Optional<String> bearerToken(Http.RequestHeader request) {
        return request.header(Http.HeaderNames.AUTHORIZATION)
                .filter(value -> value.regionMatches(true, 0, "Bearer ", 0, 7))
                .map(value -> value.substring(7).trim())
                .filter(value -> !value.isEmpty());
    }
}
