package io.meterway.persistence.repository;

import io.meterway.persistence.entity.UsageAggregateEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface UsageAggregateRepository extends CrudRepository<UsageAggregateEntity, UUID> {

    Optional<UsageAggregateEntity> findByCustomerIdAndMeterCodeAndPeriodStart(
            UUID customerId, String meterCode, Instant periodStart);

    List<UsageAggregateEntity> findByTenantIdAndPeriodStart(UUID tenantId, Instant periodStart);

    List<UsageAggregateEntity> findByCustomerIdAndPeriodStart(UUID customerId, Instant periodStart);

    /**
     * Инкрементальное слияние агрегата. Один запрос вместо чтения, изменения и записи:
     * конкурирующие консьюмеры не конфликтуют, потому что арифметику делает база.
     */
    @Query("""
            insert into usage_aggregates
                (id, tenant_id, customer_id, meter_code, period_start, period_end,
                 aggregation, value, event_count, last_event_at, updated_at, version)
            values (:id, :tenantId, :customerId, :meterCode, :periodStart, :periodEnd,
                    :aggregation, :value, :eventCount, :lastEventAt, now(), 0)
            on conflict (customer_id, meter_code, period_start) do update
               set value = case usage_aggregates.aggregation
                               when 'SUM' then usage_aggregates.value + excluded.value
                               when 'MAX' then greatest(usage_aggregates.value, excluded.value)
                               else excluded.value
                           end,
                   event_count   = usage_aggregates.event_count + excluded.event_count,
                   last_event_at = greatest(usage_aggregates.last_event_at, excluded.last_event_at),
                   updated_at    = now(),
                   version       = usage_aggregates.version + 1
            """)
    long merge(UUID id, UUID tenantId, UUID customerId, String meterCode,
               Instant periodStart, Instant periodEnd, String aggregation,
               BigDecimal value, long eventCount, Instant lastEventAt);

    /**
     * Полная замена агрегата пересчитанным значением.
     * <p>
     * Отличается от {@link #merge} тем, что не прибавляет, а записывает: пересчёт периода
     * из сырых событий уже содержит весь объём, и повторное сложение с инкрементальным
     * значением удвоило бы потребление в счёте.
     */
    @Query("""
            insert into usage_aggregates
                (id, tenant_id, customer_id, meter_code, period_start, period_end,
                 aggregation, value, event_count, last_event_at, updated_at, version)
            values (:id, :tenantId, :customerId, :meterCode, :periodStart, :periodEnd,
                    :aggregation, :value, :eventCount, :lastEventAt, now(), 0)
            on conflict (customer_id, meter_code, period_start) do update
               set value         = excluded.value,
                   event_count   = excluded.event_count,
                   last_event_at = excluded.last_event_at,
                   updated_at    = now(),
                   version       = usage_aggregates.version + 1
            """)
    long replace(UUID id, UUID tenantId, UUID customerId, String meterCode,
                 Instant periodStart, Instant periodEnd, String aggregation,
                 BigDecimal value, long eventCount, Instant lastEventAt);
}
