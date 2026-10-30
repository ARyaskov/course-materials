package beacon.domain;

import java.time.Instant;

/**
 * Ключ доступа к API. В базе хранится только префикс и хеш секретной части:
 * полный ключ показывается пользователю один раз при создании.
 */
public record ApiKey(
        long id,
        long orgId,
        String name,
        String prefix,
        String secretHash,
        Instant createdAt,
        Instant lastUsedAt,
        Instant revokedAt) {

    public boolean isActive() {
        return revokedAt == null;
    }
}
