package io.meterway.audit;

import io.meterway.security.TenantContextElement;
import io.micronaut.aop.InterceptorBean;
import io.micronaut.aop.MethodInterceptor;
import io.micronaut.aop.MethodInvocationContext;
import io.micronaut.core.order.Ordered;
import io.micronaut.core.type.MutableArgumentValue;
import jakarta.inject.Singleton;

import java.time.Clock;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Запись операции в журнал аудита.
 * <p>
 * Порядок — снаружи транзакции, но внутри измерения: запись аудита попадает
 * в ту же транзакцию, что и сама операция.
 * <p>
 * Следствие, которое надо понимать: запись со статусом FAILURE откатится вместе
 * с операцией. Это цена атомарности аудита с операцией; журнал <b>попыток</b> —
 * другая задача, и решается он метриками и логом, а не таблицей.
 */
@Singleton
@InterceptorBean(Audited.class)
public class AuditInterceptor implements MethodInterceptor<Object, Object>, Ordered {

    private final AuditRepository audit;
    private final Clock clock;

    public AuditInterceptor(AuditRepository audit, Clock clock) {
        this.audit = audit;
        this.clock = clock;
    }

    @Override
    public Object intercept(MethodInvocationContext<Object, Object> context) {
        String action = context.stringValue(Audited.class)
                .filter(value -> !value.isBlank())
                .orElseGet(context::getMethodName);

        UUID tenantId = TenantContextElement.currentTenantId().orElse(null);
        String principal = TenantContextElement.currentPrincipal().orElse("system");

        Map<String, Object> details = context.booleanValue(Audited.class, "arguments").orElse(false)
                ? capture(context)
                : Map.of();

        try {
            Object result = context.proceed();
            record(tenantId, principal, action, "SUCCESS", details, null);
            return result;
        } catch (RuntimeException e) {
            record(tenantId, principal, action, "FAILURE", details, e.getClass().getSimpleName());
            throw e;
        }
    }

    private void record(UUID tenantId, String principal, String action,
                        String outcome, Map<String, Object> details, String failure) {
        audit.save(new AuditEntry(UUID.randomUUID(), tenantId, principal, action,
                outcome, failure, details, clock.instant()));
    }

    private Map<String, Object> capture(MethodInvocationContext<Object, Object> context) {
        Map<String, Object> captured = new LinkedHashMap<>();
        for (Map.Entry<String, MutableArgumentValue<?>> entry : context.getParameters().entrySet()) {
            Object value = entry.getValue().getValue();
            captured.put(entry.getKey(), value instanceof UUID uuid ? uuid.toString() : String.valueOf(value));
        }
        return captured;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE + 20;
    }
}
