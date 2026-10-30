package beacon.security;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import play.mvc.With;

/**
 * Требует валидный API-ключ. Вешается на класс контроллера или на отдельное действие;
 * после успешной проверки в атрибутах запроса лежит {@link SecurityKeys#ORG_SLUG}.
 */
@With(ApiKeyAction.class)
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
public @interface ApiKeyAuthenticated {}
