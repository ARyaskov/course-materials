package io.meterway.persistence.repository;

import io.meterway.persistence.entity.OutboxMessageEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface OutboxRepository extends CrudRepository<OutboxMessageEntity, UUID> {

    @Query("""
            select * from outbox_messages
             where published_at is null
             order by created_at
             limit :limit
             for update skip locked
            """)
    List<OutboxMessageEntity> lockUnpublished(int limit);

    @Query("update outbox_messages set published_at = :publishedAt where id = any(:ids)")
    long markPublished(UUID[] ids, Instant publishedAt);

    /**
     * Возраст самого старого неопубликованного сообщения в секундах.
     * <p>
     * Отдельный запрос вместо чтения строки: gauge опрашивается каждые 15 секунд,
     * и вытаскивать сущность целиком ради одной величины незачем. Частичный индекс
     * outbox_unpublished_idx делает запрос дешёвым независимо от размера таблицы.
     */
    @Query("select coalesce(extract(epoch from now() - min(created_at)), 0)::bigint "
            + "from outbox_messages where published_at is null")
    long oldestUnpublishedAgeSeconds();

    long countByPublishedAtIsNull();
}
