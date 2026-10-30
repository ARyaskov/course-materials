package io.meterway.persistence.repository;

import io.meterway.persistence.entity.IdempotencyId;
import io.meterway.persistence.entity.IdempotencyRecord;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface IdempotencyRepository extends CrudRepository<IdempotencyRecord, IdempotencyId> {

    Optional<IdempotencyRecord> findByIdTenantIdAndIdIdempotencyKey(UUID tenantId, String idempotencyKey);

    /**
     * Вставка «первым выигрывает». {@code on conflict do nothing} возвращает 0 изменённых строк,
     * если ключ уже занят: это и есть сигнал дубликата, полученный без гонки между select и insert.
     */
    @Query("""
            insert into ingest_idempotency (tenant_id, idempotency_key, body_fingerprint, event_id, occurred_at)
            values (:tenantId, :idempotencyKey, :fingerprint, :eventId, :occurredAt)
            on conflict (tenant_id, idempotency_key) do nothing
            """)
    long claim(UUID tenantId, String idempotencyKey, String fingerprint, UUID eventId, Instant occurredAt);

    @Query("""
            select tenant_id, idempotency_key, body_fingerprint, event_id, occurred_at, created_at
              from ingest_idempotency
             where tenant_id = :tenantId and idempotency_key = any(:keys)
            """)
    List<IdempotencyRecord> findClaimed(UUID tenantId, String[] keys);

    @Query("delete from ingest_idempotency where created_at < :before")
    long purgeOlderThan(Instant before);
}
