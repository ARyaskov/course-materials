package modules;

import beacon.security.ApiKeyService;
import beacon.security.PasswordHasher;
import com.google.inject.AbstractModule;

public class SecurityModule extends AbstractModule {

    @Override
    protected void configure() {
        bind(PasswordHasher.class).asEagerSingleton();
        bind(ApiKeyService.class).asEagerSingleton();
    }
}
