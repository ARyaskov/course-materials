package io.meterway.aop;

import io.meterway.billing.PeriodClosingService;
import io.meterway.ingest.UsageIngestService;
import io.meterway.metering.AggregationService;
import io.micronaut.context.BeanContext;
import io.micronaut.inject.BeanDefinition;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import io.micronaut.transaction.annotation.Transactional;
import jakarta.inject.Inject;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Инварианты AOP, нарушение которых происходит молча.
 * <p>
 * Второй тест обходит все бины проекта и падает в момент добавления {@code private}
 * к транзакционному методу — то есть на пул-реквесте, а не через месяц по разъехавшимся данным.
 */
@MicronautTest(startApplication = false)
class AopContractTest {

    @Inject
    BeanContext beanContext;

    @Test
    @DisplayName("Транзакционные сервисы действительно перехвачены")
    void transactionalServicesAreIntercepted() {
        List<Class<?>> expected = List.of(
                PeriodClosingService.class, AggregationService.class, UsageIngestService.class);

        for (Class<?> type : expected) {
            Object bean = beanContext.getBean(type);
            assertTrue(bean.getClass().getName().contains("$Intercepted"),
                    type.getSimpleName() + " должен быть перехвачен, получен "
                            + bean.getClass().getName());
        }
    }

    @Test
    @DisplayName("Транзакционные методы не приватные и не финальные")
    void transactionalMethodsAreOverridable() {
        for (BeanDefinition<?> definition : beanContext.getAllBeanDefinitions()) {
            Class<?> type = definition.getBeanType();
            if (!type.getName().startsWith("io.meterway") || type.getName().contains("$")) {
                continue;
            }
            for (Method method : type.getDeclaredMethods()) {
                if (!method.isAnnotationPresent(Transactional.class)) {
                    continue;
                }
                String where = "%s.%s".formatted(type.getSimpleName(), method.getName());
                assertFalse(Modifier.isPrivate(method.getModifiers()),
                        "@Transactional на приватном методе: " + where);
                assertFalse(Modifier.isFinal(method.getModifiers()),
                        "@Transactional на final-методе: " + where);
            }
        }
    }
}
