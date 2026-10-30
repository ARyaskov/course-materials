package io.meterway.persistence.repository;

import io.meterway.persistence.entity.ApiKeyEntity;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.Optional;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface ApiKeyRepository extends CrudRepository<ApiKeyEntity, UUID> {

    /** Поиск по открытому префиксу: секрет никогда не участвует в запросе. */
    Optional<ApiKeyEntity> findByKeyPrefixAndRevokedAtIsNull(String keyPrefix);
}
