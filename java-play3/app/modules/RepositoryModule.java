package modules;

import beacon.config.BeaconSettings;
import beacon.db.DatabaseExecutionContext;
import beacon.repository.ApiKeyRepository;
import beacon.repository.CheckRepository;
import beacon.repository.IncidentRepository;
import beacon.repository.OrganizationRepository;
import beacon.repository.ProbeResultRepository;
import beacon.repository.ServiceRepository;
import beacon.repository.WebhookRepository;
import beacon.status.StatusService;
import com.google.inject.AbstractModule;

/**
 * Слой данных.
 *
 * <p>Guice связал бы эти классы и сам — у них есть {@code @Inject}-конструктор.
 * Явный модуль нужен по другой причине: он документирует состав слоя и даёт одно место,
 * где в тестах подменяются реализации через {@code overrides(...)}.
 */
public class RepositoryModule extends AbstractModule {

    @Override
    protected void configure() {
        bind(BeaconSettings.class).asEagerSingleton();
        bind(DatabaseExecutionContext.class).asEagerSingleton();

        bind(OrganizationRepository.class).asEagerSingleton();
        bind(ServiceRepository.class).asEagerSingleton();
        bind(CheckRepository.class).asEagerSingleton();
        bind(ProbeResultRepository.class).asEagerSingleton();
        bind(IncidentRepository.class).asEagerSingleton();
        bind(ApiKeyRepository.class).asEagerSingleton();
        bind(WebhookRepository.class).asEagerSingleton();
        bind(StatusService.class).asEagerSingleton();
    }
}
