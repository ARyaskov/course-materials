package io.meterway.observability;

import io.meterway.security.TenantContextElement;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micronaut.aop.InterceptorBean;
import io.micronaut.aop.MethodInterceptor;
import io.micronaut.aop.MethodInvocationContext;
import io.micronaut.core.order.Ordered;
import jakarta.inject.Singleton;

import java.util.Locale;
import java.util.UUID;

/**
 * Перехватчик измерения.
 * <p>
 * Порядок — самый внешний среди наблюдательных советов: измерение должно охватывать
 * и получение соединения из пула, иначе метрика покажет, что всё быстро,
 * пока пользователи ждут на исчерпанном пуле.
 * <p>
 * Исключение записывается в метрику и пробрасывается дальше: совет не должен менять
 * поведение метода при ошибке.
 */
@Singleton
@InterceptorBean(Measured.class)
public class MeasuredInterceptor implements MethodInterceptor<Object, Object>, Ordered {

    private final MeterRegistry registry;

    public MeasuredInterceptor(MeterRegistry registry) {
        this.registry = registry;
    }

    @Override
    public Object intercept(MethodInvocationContext<Object, Object> context) {
        String metric = context.stringValue(Measured.class)
                .filter(name -> !name.isBlank())
                .orElseGet(() -> "meterway.%s.%s".formatted(
                        context.getDeclaringType().getSimpleName().toLowerCase(Locale.ROOT),
                        context.getMethodName()));

        String tenant = TenantContextElement.currentTenantId().map(UUID::toString).orElse("none");

        Timer.Sample sample = Timer.start(registry);
        try {
            Object result = context.proceed();
            sample.stop(registry.timer(metric, "tenant", tenant, "outcome", "success"));
            return result;
        } catch (RuntimeException e) {
            sample.stop(registry.timer(metric, "tenant", tenant, "outcome", "failure"));
            if (context.booleanValue(Measured.class, "countFailures").orElse(true)) {
                registry.counter(metric + ".failures", "exception", e.getClass().getSimpleName()).increment();
            }
            throw e;
        }
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE + 10;
    }
}
