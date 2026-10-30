package beacon.domain;

/** Подписчик на события организации: URL и секрет для подписи тела запроса. */
public record Webhook(long id, long orgId, String url, String secret, boolean enabled) {}
