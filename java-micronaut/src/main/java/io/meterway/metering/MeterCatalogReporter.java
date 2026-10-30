package io.meterway.metering;

import io.meterway.config.MeterDefinition;
import io.micronaut.context.event.StartupEvent;
import io.micronaut.runtime.event.annotation.EventListener;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Comparator;

/**
 * Печатает активный каталог метрик при старте и падает, если он пуст.
 * <p>
 * Слушатель делает две вещи сразу: логирует то, что действительно попало в контейнер
 * (а не то, что написано в файле), и вынуждает ленивый {@link MeterCatalog} создаться на старте —
 * иначе ошибка конфигурации всплыла бы под нагрузкой, на первом же событии.
 */
@Singleton
public class MeterCatalogReporter {

    private static final Logger LOG = LoggerFactory.getLogger(MeterCatalogReporter.class);

    private final MeterCatalog catalog;

    public MeterCatalogReporter(MeterCatalog catalog) {
        this.catalog = catalog;
    }

    @EventListener
    void onStartup(StartupEvent event) {
        if (catalog.size() == 0) {
            throw new IllegalStateException(
                    "Каталог метрик пуст: не задано ни одной секции meterway.meters.*");
        }
        LOG.info("Каталог метрик: {} определений", catalog.size());
        catalog.all().stream()
                .sorted(Comparator.comparing(MeterDefinition::getCode))
                .forEach(definition -> LOG.info("  {} -> {} [{}]{}",
                        definition.getCode(),
                        definition.getAggregation(),
                        definition.getUnit(),
                        definition.isQuotaEnforced() ? " квота" : ""));
    }
}
