package io.meterway.observability;

import io.meterway.persistence.repository.OutboxRepository;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micronaut.context.annotation.Context;
import io.micronaut.context.annotation.Requires;

/**
 * Отставание outbox как метрика.
 * <p>
 * Индикатор {@code /health} отвечает «плохо или нет» и виден только тому, кто его опросит.
 * Метрика даёт историю и позволяет построить алерт: правило
 * {@code meterway_outbox_lag_seconds > 300} в ops/alerts.yml опирается именно на неё.
 * <p>
 * Значение вычисляется в момент опроса, поэтому запрос обязан быть дешёвым: частичный
 * индекс по неопубликованным строкам делает его таким независимо от размера таблицы.
 * <p>
 * Скоуп {@code @Context}, а не {@code @Singleton}: синглтон создаётся лениво, при первом
 * внедрении, а этот бин никто не внедряет — он существует ради побочного эффекта в
 * конструкторе. Ленивый бин не был бы создан никогда, и метрики не появились бы.
 */
@Context
@Requires(beans = OutboxRepository.class)
public class OutboxLagGauge {

    public OutboxLagGauge(OutboxRepository outbox, MeterRegistry registry) {
        Gauge.builder("meterway.outbox.lag.seconds", outbox,
                        repository -> repository.oldestUnpublishedAgeSeconds())
                .description("Возраст самого старого неопубликованного сообщения outbox")
                .register(registry);

        Gauge.builder("meterway.outbox.pending", outbox,
                        repository -> repository.countByPublishedAtIsNull())
                .description("Число неопубликованных сообщений outbox")
                .register(registry);
    }
}
