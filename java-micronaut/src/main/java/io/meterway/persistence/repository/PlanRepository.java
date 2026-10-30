package io.meterway.persistence.repository;

import io.meterway.persistence.entity.PlanEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface PlanRepository extends CrudRepository<PlanEntity, UUID> {

    Optional<PlanEntity> findByTenantIdAndCode(UUID tenantId, String code);

    List<PlanEntity> findByTenantIdAndActiveTrue(UUID tenantId);
}
