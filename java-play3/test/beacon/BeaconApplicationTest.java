package beacon;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Before;
import play.Application;
import play.inject.guice.GuiceApplicationBuilder;
import play.test.Helpers;
import play.test.WithApplication;

/**
 * Базовый класс тестов: приложение поднимается на H2 в памяти, эволюции применяются
 * автоматически, планировщик проб выключен.
 *
 * <p>Отдельно разрешены все Host-заголовки: {@code AllowedHostsFilter} в конфигурации
 * прода настроен на конкретные хосты, а {@code Helpers.fakeRequest} их не проставляет.
 * Это первая ошибка, на которую натыкаются при первом же тесте контроллера.
 */
public abstract class BeaconApplicationTest extends WithApplication {

    @Override
    protected Application provideApplication() {
        Map<String, Object> config = new HashMap<>(
                Helpers.inMemoryDatabase("default", Map.of("MODE", "PostgreSQL", "DB_CLOSE_DELAY", "-1")));
        config.put("play.evolutions.db.default.autoApply", true);
        config.put("play.evolutions.db.default.autoApplyDowns", true);
        config.put("play.filters.hosts.allowed", List.of("."));
        config.put("beacon.probe.enabled", false);
        config.put("beacon.notify.enabled", false);
        config.put("beacon.status-page.cache-ttl", "1 second");

        return new GuiceApplicationBuilder()
                .configure(config)
                .build();
    }

    /**
     * Эволюции применяются явно. Автоприменение на старте зависит от режима и порядка
     * инициализации, а тест должен получать одинаковую схему при каждом запуске.
     * Метод выполняется после старта приложения, который делает {@link WithApplication}.
     */
    @Before
    public void applyEvolutions() {
        // Форсируем создание компонента эволюций: он связан как eager singleton,
        // но тестовое приложение собирается в режиме DEVELOPMENT, и полагаться на
        // порядок инициализации в тесте не стоит. С autoApply = true обращение к нему
        // применяет все скрипты из conf/evolutions/default.
        app.injector().instanceOf(play.api.db.evolutions.ApplicationEvolutions.class);
    }
}
