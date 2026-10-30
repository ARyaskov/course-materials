package io.meterway.persistence.repository;

import io.meterway.persistence.entity.SubscriptionEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface SubscriptionRepository extends CrudRepository<SubscriptionEntity, UUID> {

    Optional<SubscriptionEntity> findByCustomerIdAndEndedAtIsNull(UUID customerId);

    List<SubscriptionEntity> findByTenantIdAndStartedAtLessThanEquals(UUID tenantId, Instant moment);
}
