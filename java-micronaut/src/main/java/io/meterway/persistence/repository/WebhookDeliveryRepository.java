package io.meterway.persistence.repository;

import io.meterway.persistence.entity.WebhookDeliveryEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface WebhookDeliveryRepository extends CrudRepository<WebhookDeliveryEntity, UUID> {

    /**
     * Выборка порции доставок с блокировкой строк: {@code for update skip locked}
     * позволяет нескольким подам разбирать очередь без координации между собой.
     */
    @Query("""
            select * from webhook_deliveries
             where status = 'PENDING' and next_attempt_at <= :now
             order by next_attempt_at
             limit :limit
             for update skip locked
            """)
    List<WebhookDeliveryEntity> lockDue(Instant now, int limit);

    @Query("""
            update webhook_deliveries
               set status = :status,
                   attempts = attempts + 1,
                   next_attempt_at = :nextAttemptAt,
                   last_error = :lastError,
                   delivered_at = :deliveredAt
             where id = :id
            """)
    long recordAttempt(UUID id, String status, Instant nextAttemptAt, String lastError, Instant deliveredAt);
}
