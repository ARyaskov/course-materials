package io.meterway.aop;

import io.micronaut.cache.annotation.Cacheable;
import io.micronaut.context.ApplicationContext;
import jakarta.inject.Singleton;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Проверка того, как в Micronaut ведёт себя вызов советованного метода через {@code this}.
 * <p>
 * В рефлексивных контейнерах бин оборачивается прокси-объектом, и внутренний вызов минует совет.
 * Micronaut генерирует <b>подкласс</b>, и бин — это экземпляр подкласса, поэтому обычная
 * виртуальная диспетчеризация доводит вызов до перехватчика. Тест фиксирует это поведение,
 * потому что интуиция, принесённая из Spring, здесь подводит.
 */
class SelfInvocationTest {

    @Singleton
    static class Probe {

        final AtomicInteger invocations = new AtomicInteger();

        String viaThis(String key) {
            return cached(key);
        }

        @Cacheable("probe")
        String cached(String key) {
            return key + "-" + invocations.incrementAndGet();
        }
    }

    @Test
    @DisplayName("Вызов через this проходит через перехватчик: бин — это сгенерированный подкласс")
    void selfInvocationIsIntercepted() {
        try (ApplicationContext context = ApplicationContext.run(
                Map.of("micronaut.caches.probe.maximum-size", "100"), "unit")) {

            Probe probe = context.getBean(Probe.class);

            assertTrue(probe.getClass().getName().contains("$Intercepted"),
                    "бин должен быть сгенерированным подклассом, а не исходным классом");

            probe.viaThis("a");
            probe.viaThis("a");
            assertEquals(1, probe.invocations.get(), "второй вызов должен обслужить кэш");

            probe.cached("b");
            probe.cached("b");
            assertEquals(2, probe.invocations.get());
        }
    }
}
