package io.meterway.persistence.repository;

import io.meterway.persistence.entity.InvoiceEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface InvoiceRepository extends CrudRepository<InvoiceEntity, UUID> {

    Optional<InvoiceEntity> findBySubscriptionIdAndPeriodStart(UUID subscriptionId, Instant periodStart);

    List<InvoiceEntity> findByTenantIdAndPeriodStart(UUID tenantId, Instant periodStart);

    Optional<InvoiceEntity> findByIdAndTenantId(UUID id, UUID tenantId);
}
