package beacon.domain;

/** Проверка вместе с тем, что нужно для публикации события: ключ сервиса и slug организации. */
public record CheckContext(Check check, String serviceKey, String orgSlug) {}
