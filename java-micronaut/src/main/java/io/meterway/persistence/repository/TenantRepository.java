package io.meterway.persistence.repository;

import io.meterway.persistence.entity.TenantEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface TenantRepository extends CrudRepository<TenantEntity, UUID> {
}
