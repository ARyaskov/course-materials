package io.meterway.security;

import io.meterway.config.ConsoleUser;
import io.micronaut.http.HttpRequest;
import io.micronaut.security.authentication.AuthenticationFailureReason;
import io.micronaut.security.authentication.AuthenticationRequest;
import io.micronaut.security.authentication.AuthenticationResponse;
import io.micronaut.security.authentication.provider.HttpRequestAuthenticationProvider;
import jakarta.inject.Singleton;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Вход в панель по логину и паролю.
 * <p>
 * {@link HttpRequestAuthenticationProvider} — синхронный интерфейс Micronaut Security:
 * реализация вызывается из фильтра логина и возвращает готовый ответ.
 * Атрибут {@code tenantId} попадёт в claims JWT и дальше — в {@link TenantPropagationFilter}.
 */
@Singleton
public class ConsoleAuthenticationProvider<B> implements HttpRequestAuthenticationProvider<B> {

    private final Map<String, ConsoleUser> users;
    private final ApiKeyHasher hasher;

    public ConsoleAuthenticationProvider(List<ConsoleUser> users, ApiKeyHasher hasher) {
        this.users = users.stream()
                .collect(Collectors.toUnmodifiableMap(ConsoleUser::getUsername, Function.identity()));
        this.hasher = hasher;
    }

    @Override
    public AuthenticationResponse authenticate(HttpRequest<B> requestContext,
                                               AuthenticationRequest<String, String> authenticationRequest) {
        ConsoleUser user = users.get(authenticationRequest.getIdentity());
        if (user == null) {
            return AuthenticationResponse.failure(AuthenticationFailureReason.USER_NOT_FOUND);
        }
        if (!hasher.matches(authenticationRequest.getSecret(), user.getPasswordHash())) {
            return AuthenticationResponse.failure(AuthenticationFailureReason.CREDENTIALS_DO_NOT_MATCH);
        }
        return AuthenticationResponse.success(
                user.getUsername(),
                user.getRoles(),
                Map.of(MeterwayPrincipal.TENANT_ATTRIBUTE, user.getTenantId()));
    }
}
