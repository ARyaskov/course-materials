package io.meterway.security;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.security.token.Claims;
import io.micronaut.security.token.jwt.validator.GenericJwtClaimsValidator;
import jakarta.inject.Singleton;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Токен без тенанта бесполезен: любой запрос к отчётам всё равно упрётся в его отсутствие.
 * Отклонить такой токен на этапе валидации дешевле, чем разбираться в 500-й ошибке позже.
 * <p>
 * {@link GenericJwtClaimsValidator} — точка расширения Micronaut Security: все бины этого
 * интерфейса вызываются после проверки подписи, и достаточно одного {@code false},
 * чтобы токен был отвергнут.
 */
@Singleton
public class TenantClaimsValidator<T> implements GenericJwtClaimsValidator<T> {

    private static final Logger LOG = LoggerFactory.getLogger(TenantClaimsValidator.class);

    @Override
    public boolean validate(Claims claims, @Nullable T request) {
        Object tenantId = claims.get(MeterwayPrincipal.TENANT_ATTRIBUTE);
        if (tenantId == null) {
            LOG.debug("Токен отклонён: нет claim tenantId");
            return false;
        }
        try {
            java.util.UUID.fromString(tenantId.toString());
            return true;
        } catch (IllegalArgumentException e) {
            LOG.debug("Токен отклонён: tenantId не UUID: {}", tenantId);
            return false;
        }
    }
}
