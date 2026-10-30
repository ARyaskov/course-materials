package io.meterway.audit;

import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.CursoredPageable;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.GenericRepository;

import java.util.UUID;

/**
 * Журнал аудита: только запись и чтение. Методов изменения и удаления нет —
 * запись журнала не подлежит правке.
 */
@JdbcRepository(dialect = Dialect.POSTGRES)
public interface AuditRepository extends GenericRepository<AuditEntry, UUID> {

    AuditEntry save(AuditEntry entry);

    Page<AuditEntry> findByTenantIdOrderByOccurredAtDesc(UUID tenantId, CursoredPageable pageable);

    long countByTenantIdAndAction(UUID tenantId, String action);
}
