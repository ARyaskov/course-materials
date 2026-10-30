package io.meterway.security;

import io.micronaut.core.propagation.PropagatedContext;
import io.micronaut.core.propagation.PropagatedContextElement;

import java.util.Optional;
import java.util.UUID;

/**
 * Тенант, распространяемый вместе с {@link PropagatedContext}.
 * В Micronaut 5 контекст умеет ехать на {@code ScopedValue}, поэтому он переживает переход
 * на другой поток — в отличие от {@code ThreadLocal}, который на виртуальных потоках теряется.
 */
public record TenantContextElement(UUID tenantId, String principal) implements PropagatedContextElement {

    public static Optional<UUID> currentTenantId() {
        return PropagatedContext.getOrEmpty()
                .find(TenantContextElement.class)
                .map(TenantContextElement::tenantId);
    }

    public static Optional<String> currentPrincipal() {
        return PropagatedContext.getOrEmpty()
                .find(TenantContextElement.class)
                .map(TenantContextElement::principal);
    }

    public static UUID requireCurrentTenantId() {
        return currentTenantId().orElseThrow(
                () -> new IllegalStateException("Тенант не определён: вызов вне контекста запроса или задачи"));
    }
}
