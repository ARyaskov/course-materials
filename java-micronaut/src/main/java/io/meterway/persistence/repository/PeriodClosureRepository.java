package io.meterway.persistence.repository;

import io.meterway.persistence.entity.PeriodClosureEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface PeriodClosureRepository extends CrudRepository<PeriodClosureEntity, UUID> {

    Optional<PeriodClosureEntity> findByTenantIdAndPeriodStart(UUID tenantId, Instant periodStart);
}
