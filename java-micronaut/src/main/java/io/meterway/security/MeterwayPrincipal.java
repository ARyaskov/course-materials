package io.meterway.security;

import io.micronaut.security.authentication.Authentication;

import java.util.Optional;
import java.util.UUID;

/**
 * Разбор Authentication в доменные термины. Атрибут {@code tenantId} кладут оба способа входа:
 * провайдер API-ключа и генератор JWT.
 */
public final class MeterwayPrincipal {

    public static final String TENANT_ATTRIBUTE = "tenantId";
    public static final String KEY_ID_ATTRIBUTE = "apiKeyId";

    private MeterwayPrincipal() {
    }

    public static UUID tenantId(Authentication authentication) {
        return findTenantId(authentication).orElseThrow(
                () -> new IllegalStateException("В Authentication нет атрибута tenantId"));
    }

    public static Optional<UUID> findTenantId(Authentication authentication) {
        Object raw = authentication.getAttributes().get(TENANT_ATTRIBUTE);
        return switch (raw) {
            case UUID uuid -> Optional.of(uuid);
            case String string -> Optional.of(UUID.fromString(string));
            case null, default -> Optional.empty();
        };
    }

    public static Optional<UUID> apiKeyId(Authentication authentication) {
        Object raw = authentication.getAttributes().get(KEY_ID_ATTRIBUTE);
        return raw instanceof String string ? Optional.of(UUID.fromString(string)) : Optional.empty();
    }
}
