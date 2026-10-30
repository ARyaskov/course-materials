package io.meterway.persistence.repository;

import io.meterway.persistence.entity.WebhookEndpointEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface WebhookEndpointRepository extends CrudRepository<WebhookEndpointEntity, UUID> {

    List<WebhookEndpointEntity> findByTenantIdAndActiveTrue(UUID tenantId);

    /** Отключение эндпоинта, получатель которого ответил {@code 410 Gone}. */
    @Query("update webhook_endpoints set active = false where id = :id")
    long deactivate(UUID id);
}
