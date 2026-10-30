package io.meterway.metering;

import io.meterway.domain.AggregationType;
import io.meterway.domain.UnknownMeterException;
import io.micronaut.context.ApplicationContext;
import io.micronaut.context.exceptions.BeanInstantiationException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Каталог собирается из конфигурации, поэтому проверять его удобно на самодельном контексте.
 * <p>
 * Окружение указано явно ({@code unit}) вместо выводимого {@code test}: так не загружается
 * application-test.properties, а вместе с ним — конфигурация PostgreSQL и Redis.
 * Тест поднимается за десятки миллисекунд и не трогает Docker.
 */
class MeterCatalogTest {

    private static final String UNIT = "unit";

    @Test
    @DisplayName("Секции meterway.meters.* добавляются к каталогу, код берётся из свойства code")
    void buildsCatalogFromConfiguration() {
        try (ApplicationContext context = ApplicationContext.run(Map.of(
                "meterway.meters.test-alpha.code", "test.alpha",
                "meterway.meters.test-alpha.aggregation", "SUM",
                "meterway.meters.test-alpha.unit", "REQUEST",
                "meterway.meters.test-alpha.quota-enforced", "true",
                "meterway.meters.test-beta.code", "test.beta",
                "meterway.meters.test-beta.aggregation", "UNIQUE_COUNT",
                "meterway.meters.test-beta.unique-by", "user_id"), UNIT)) {

            MeterCatalog catalog = context.getBean(MeterCatalog.class);

            assertEquals(AggregationType.SUM, catalog.require("test.alpha").getAggregation());
            assertTrue(catalog.require("test.alpha").isQuotaEnforced());
            assertEquals("user_id", catalog.require("test.beta").getUniqueBy());
            assertTrue(catalog.contains("api.requests"), "базовый каталог тоже загружен");
        }
    }

    @Test
    @DisplayName("Имя секции без свойства code само становится кодом метрики")
    void fallsBackToSectionName() {
        try (ApplicationContext context = ApplicationContext.run(Map.of(
                "meterway.meters.queue-depth.aggregation", "MAX"), UNIT)) {

            assertEquals(AggregationType.MAX,
                    context.getBean(MeterCatalog.class).require("queue-depth").getAggregation());
        }
    }

    @Test
    @DisplayName("Обращение к незарегистрированной метрике падает сразу, а не при тарификации")
    void failsFastOnUnknownMeter() {
        try (ApplicationContext context = ApplicationContext.run(Map.of(), UNIT)) {
            MeterCatalog catalog = context.getBean(MeterCatalog.class);

            assertThrows(UnknownMeterException.class, () -> catalog.require("api.unknown"));
            assertTrue(catalog.find("api.unknown").isEmpty());
        }
    }

    @Test
    @DisplayName("UNIQUE_COUNT без unique-by останавливает старт контекста")
    void rejectsUniqueCountWithoutProperty() {
        // Каталог создаётся на старте (его требует MeterCatalogReporter),
        // поэтому исключение прилетает из ApplicationContext.run, а не из getBean.
        BeanInstantiationException error = assertThrows(BeanInstantiationException.class,
                () -> ApplicationContext.run(Map.of(
                        "meterway.meters.test-gamma.code", "test.gamma",
                        "meterway.meters.test-gamma.aggregation", "UNIQUE_COUNT"), UNIT));

        assertTrue(error.getMessage().contains("unique-by"));
    }

    @Test
    @DisplayName("Пустой каталог останавливает старт приложения")
    void rejectsEmptyCatalog() {
        MeterCatalog empty = new MeterCatalog(java.util.List.of());
        MeterCatalogReporter reporter = new MeterCatalogReporter(empty);

        assertThrows(IllegalStateException.class, () -> reporter.onStartup(null));
    }
}
