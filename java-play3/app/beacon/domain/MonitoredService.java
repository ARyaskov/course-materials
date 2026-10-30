package beacon.domain;

import java.time.Instant;

/**
 * Наблюдаемый сервис организации. Именно он показывается строкой на статус-странице,
 * а его состояние вычисляется по результатам проверок ({@link Check}).
 */
public record MonitoredService(
        long id,
        long orgId,
        ServiceKey key,
        String name,
        String description,
        int position,
        Instant createdAt) {}
