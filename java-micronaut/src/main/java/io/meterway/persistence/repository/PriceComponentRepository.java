package io.meterway.persistence.repository;

import io.meterway.persistence.entity.PriceComponentEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface PriceComponentRepository extends CrudRepository<PriceComponentEntity, UUID> {

    List<PriceComponentEntity> findByPlanIdOrderByPosition(UUID planId);
}
