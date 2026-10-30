package io.meterway.persistence.repository;

import io.meterway.persistence.entity.CustomerEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.PageableRepository;

import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface CustomerRepository extends PageableRepository<CustomerEntity, UUID> {

    Optional<CustomerEntity> findByTenantIdAndExternalRef(UUID tenantId, String externalRef);

    Optional<CustomerEntity> findByIdAndTenantId(UUID id, UUID tenantId);

    Page<CustomerEntity> findByTenantId(UUID tenantId, Pageable pageable);

    boolean existsByIdAndTenantId(UUID id, UUID tenantId);
}
