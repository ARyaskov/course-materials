package io.meterway.billing;

import io.meterway.persistence.entity.UsageEventEntity;
import io.meterway.persistence.repository.UsageEventFilter;
import io.meterway.persistence.repository.UsageEventRepository;
import io.meterway.persistence.repository.UsageEventSpecifications;
import io.micronaut.data.model.Page;
import io.micronaut.data.model.Pageable;
import io.micronaut.data.repository.jpa.criteria.PredicateSpecification;
import jakarta.inject.Singleton;

import java.util.UUID;

/**
 * Поиск событий по произвольному набору условий.
 * <p>
 * Фильтр тенанта — база, к которой всё добавляется, и задан он до любых ветвлений.
 * Собрать спецификацию, возвращающую чужие события, структурно невозможно.
 */
@Singleton
public class UsageEventQueryService {

    private final UsageEventRepository events;

    public UsageEventQueryService(UsageEventRepository events) {
        this.events = events;
    }

    public Page<UsageEventEntity> search(UUID tenantId, UsageEventFilter filter, Pageable pageable) {
        PredicateSpecification<UsageEventEntity> spec = UsageEventSpecifications.tenantIs(tenantId)
                .and(UsageEventSpecifications.customerIs(filter.customerId()))
                .and(UsageEventSpecifications.meterIn(filter.meterCodes()))
                .and(UsageEventSpecifications.occurredWithin(filter.from(), filter.to()))
                .and(UsageEventSpecifications.quantityAtLeast(filter.minQuantity()))
                .and(UsageEventSpecifications.sourceIs(filter.source()));

        return events.findAll(spec, pageable);
    }

    public long count(UUID tenantId, UsageEventFilter filter) {
        return events.count(UsageEventSpecifications.tenantIs(tenantId)
                .and(UsageEventSpecifications.customerIs(filter.customerId()))
                .and(UsageEventSpecifications.meterIn(filter.meterCodes()))
                .and(UsageEventSpecifications.occurredWithin(filter.from(), filter.to())));
    }
}
