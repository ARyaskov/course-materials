package beacon.security;

import play.libs.typedmap.TypedKey;

/**
 * Типизированные ключи атрибутов запроса.
 *
 * <p>Так фильтры и action composition передают данные в контроллер, не превращая
 * {@code Http.Request} в свалку строковых заголовков и не заводя ThreadLocal.
 */
public final class SecurityKeys {

    /** Организация, от имени которой выполняется запрос (API-ключ или сессия админки). */
    public static final TypedKey<String> ORG_SLUG = TypedKey.create("beacon.orgSlug");

    /** Идентификатор запроса, он же значение заголовка X-Request-Id и MDC-поля requestId. */
    public static final TypedKey<String> REQUEST_ID = TypedKey.create("beacon.requestId");

    /** Идентификатор использованного API-ключа: нужен для аудита и rate limiting. */
    public static final TypedKey<Long> API_KEY_ID = TypedKey.create("beacon.apiKeyId");

    private SecurityKeys() {}
}
