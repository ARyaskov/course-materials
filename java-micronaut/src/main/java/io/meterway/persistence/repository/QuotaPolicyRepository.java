package io.meterway.persistence.repository;

import io.meterway.persistence.entity.QuotaPolicyEntity;
import io.micronaut.data.annotation.Query;
import io.micronaut.data.jdbc.annotation.JdbcRepository;
import io.micronaut.data.model.query.builder.sql.Dialect;
import io.micronaut.data.repository.CrudRepository;

import java.util.List;
import java.util.UUID;

@JdbcRepository(dialect = Dialect.POSTGRES)
public interface QuotaPolicyRepository extends CrudRepository<QuotaPolicyEntity, UUID> {

    /**
     * Политики, применимые к паре (клиент, метрика): персональная перекрывает общую,
     * поэтому персональные идут первыми.
     */
    @Query("""
            select * from quota_policies
             where tenant_id = :tenantId
               and meter_code = :meterCode
               and enabled
               and (customer_id = :customerId or customer_id is null)
             order by customer_id nulls last
            """)
    List<QuotaPolicyEntity> findApplicable(UUID tenantId, UUID customerId, String meterCode);

    List<QuotaPolicyEntity> findByTenantIdAndEnabledTrue(UUID tenantId);
}
