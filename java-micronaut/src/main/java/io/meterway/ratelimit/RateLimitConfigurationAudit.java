package io.meterway.ratelimit;

import io.micronaut.context.BeanContext;
import io.micronaut.context.event.StartupEvent;
import io.micronaut.runtime.event.annotation.EventListener;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Проверяет на старте, что для каждой аннотации {@code @RateLimited} настроена политика.
 * <p>
 * Опечатка в имени политики иначе обнаружилась бы при первом вызове — то есть у пользователя.
 * Обход определений бинов дёшев: они уже загружены.
 * <p>
 * Зависимости приходят через конструктор, а не параметрами метода: слушатель
 * {@code @EventListener} принимает ровно один аргумент — само событие.
 */
@Singleton
public class RateLimitConfigurationAudit {

    private static final Logger LOG = LoggerFactory.getLogger(RateLimitConfigurationAudit.class);

    private final BeanContext beanContext;
    private final Set<String> configured;

    public RateLimitConfigurationAudit(BeanContext beanContext, List<RateLimitPolicy> policies) {
        this.beanContext = beanContext;
        this.configured = policies.stream()
                .map(RateLimitPolicy::getName)
                .collect(Collectors.toUnmodifiableSet());
    }

    @EventListener
    void onStartup(StartupEvent event) {
        List<String> missing = beanContext.getAllBeanDefinitions().stream()
                .filter(definition -> definition.getBeanType().getName().startsWith("io.meterway"))
                .flatMap(definition -> definition.getExecutableMethods().stream())
                .filter(method -> method.hasAnnotation(RateLimited.class))
                .map(method -> method.stringValue(RateLimited.class).orElseThrow())
                .distinct()
                .filter(name -> !configured.contains(name))
                .toList();

        if (!missing.isEmpty()) {
            throw new IllegalStateException("Политики лимита не настроены: " + String.join(", ", missing));
        }
        LOG.info("Политики лимита проверены: {}", configured);
    }
}
