package io.meterway.security;

import io.micronaut.core.order.Ordered;
import io.micronaut.core.propagation.PropagatedContext;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.RequestFilter;
import io.micronaut.http.annotation.ServerFilter;
import io.micronaut.http.filter.FilterContinuation;
import io.micronaut.http.filter.ServerFilterPhase;
import io.micronaut.security.authentication.Authentication;
import org.reactivestreams.Publisher;
import org.slf4j.MDC;

import java.security.Principal;
import java.util.Optional;
import java.util.UUID;

/**
 * Кладёт тенанта в {@link PropagatedContext} на время обработки запроса.
 * <p>
 * Продолжение объявлено как {@code FilterContinuation<Publisher<HttpResponse<?>>>}, а не
 * как {@code FilterContinuation<HttpResponse<?>>}. Разница не косметическая: блокирующая
 * форма выполняет маршрут на другом потоке и контекст туда не доезжает — в частности,
 * при {@code @ExecuteOn(TaskExecutors.BLOCKING)} на контроллере. Реактивная форма
 * оборачивает подписку, и контекст переживает переход на другой поток.
 * <p>
 * Контекст распространяется через {@code propagate(Supplier)}, а не через try-with-resources:
 * форма со {@code Scope} объявлена устаревшей, потому что не ложится на {@code ScopedValue},
 * который в Micronaut 5 может стоять за реализацией распространения контекста.
 */
@ServerFilter(patterns = {"/v1/**", "/graphql"})
public class TenantPropagationFilter implements Ordered {

    public static final String MDC_TENANT = "tenantId";

    @RequestFilter
    public Publisher<HttpResponse<?>> propagateTenant(
            HttpRequest<?> request,
            FilterContinuation<Publisher<HttpResponse<?>>> continuation) {

        Optional<UUID> tenantId = request.getUserPrincipal(Authentication.class)
                .flatMap(MeterwayPrincipal::findTenantId);

        if (tenantId.isEmpty()) {
            return continuation.proceed();
        }

        UUID tenant = tenantId.get();
        String principal = request.getUserPrincipal().map(Principal::getName).orElse("unknown");

        PropagatedContext context = PropagatedContext.getOrEmpty()
                .plus(new TenantContextElement(tenant, principal));

        MDC.put(MDC_TENANT, tenant.toString());
        try {
            return context.propagate(continuation::proceed);
        } finally {
            MDC.remove(MDC_TENANT);
        }
    }

    /**
     * Строго после {@code SecurityFilter}: он стоит в фазе {@link ServerFilterPhase#SECURITY}
     * (порядок 39000), и фильтр с меньшим порядком получил бы пустой {@code getUserPrincipal()}
     * — молча, без единой ошибки. Симптом такой перестановки — {@code tenant=none} в логах
     * и {@code IllegalStateException} в первом же коде, которому нужен тенант из контекста.
     */
    @Override
    public int getOrder() {
        return ServerFilterPhase.SECURITY.after();
    }
}
