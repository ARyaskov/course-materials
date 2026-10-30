package io.meterway.persistence.repository;

import io.meterway.persistence.entity.UsageEventEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.CursoredPageable;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.GenericRepository;
import io.micronaut.data.repository.jpa.JpaSpecificationExecutor;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface UsageEventRepository
        extends GenericRepository<UsageEventEntity, UUID>, JpaSpecificationExecutor<UsageEventEntity> {

    UsageEventEntity save(UsageEventEntity event);

    List<UsageEventEntity> saveAll(Iterable<UsageEventEntity> events);

    /**
     * Агрегация за окно одним запросом. Возвращает проекцию, а не сущности:
     * тянуть миллион строк в приложение, чтобы их сложить, — не вариант.
     * <p>
     * Псевдонимы колонок пишутся в snake_case: Micronaut Data ищет в ResultSet имя,
     * полученное из имени свойства DTO по той же стратегии именования, что и для сущностей.
     * Псевдоним {@code as sumValue} дал бы ошибку «column not found» в рантайме.
     */
    @Query("""
            select tenant_id,
                   customer_id,
                   meter_code,
                   sum(quantity)    as sum_value,
                   max(quantity)    as max_value,
                   count(*)         as event_count,
                   max(occurred_at) as last_event_at
              from usage_events
             where tenant_id = :tenantId
               and occurred_at >= :from
               and occurred_at <  :to
             group by tenant_id, customer_id, meter_code
            """)
    List<UsageRollup> rollup(UUID tenantId, Instant from, Instant to);

    @Query("""
            select count(distinct properties ->> :property)
              from usage_events
             where tenant_id = :tenantId
               and customer_id = :customerId
               and meter_code = :meterCode
               and occurred_at >= :from
               and occurred_at <  :to
            """)
    long countDistinctProperty(UUID tenantId, UUID customerId, String meterCode,
                               String property, Instant from, Instant to);

    Page<UsageEventEntity> findByTenantIdAndCustomerIdOrderByOccurredAtDesc(
            UUID tenantId, UUID customerId, CursoredPageable pageable);

    long countByTenantIdAndOccurredAtBetween(UUID tenantId, Instant from, Instant to);
}
