package beacon.domain;

import java.time.Instant;

/** Владелец статус-страницы: организация, у которой есть сервисы и проверки. */
public record Organization(long id, String slug, String name, Instant createdAt) {}
