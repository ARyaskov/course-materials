package io.meterway.ratelimit;

import io.micronaut.aop.Around;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

/** Лимит частоты обращений на тенанта. Числа задаются политикой в конфигурации. */
@Documented
@Retention(RUNTIME)
@Target(METHOD)
@Around
public @interface RateLimited {

    /** Имя политики в конфигурации {@code meterway.rate-limits.*}. */
    String value();
}
