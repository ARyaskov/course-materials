package io.meterway.audit;

import io.micronaut.aop.Around;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

/**
 * Записывает факт выполнения операции в журнал аудита.
 * <p>
 * Ставится только на изменяющие операции: аудит чтений даёт объём, в котором
 * невозможно найти нужное событие.
 */
@Documented
@Retention(RUNTIME)
@Target(METHOD)
@Around
public @interface Audited {

    /** Действие в журнале. По умолчанию — имя метода. */
    String value() default "";

    /**
     * Записывать ли аргументы. По умолчанию нет: среди них могут быть
     * персональные данные и секреты.
     */
    boolean arguments() default false;
}
