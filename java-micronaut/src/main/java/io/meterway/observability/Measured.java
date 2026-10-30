package io.meterway.observability;

import io.micronaut.aop.Around;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

/**
 * Измеряет время выполнения метода и записывает его в Micrometer.
 * <p>
 * В отличие от {@code @Timed} из micrometer-annotation, добавляет тег тенанта — без него
 * метрика тарификации не отвечает на вопрос «у какого тенанта расчёт стал дольше».
 */
@Documented
@Retention(RUNTIME)
@Target(METHOD)
@Around
public @interface Measured {

    /** Имя метрики. По умолчанию выводится из имени класса и метода. */
    String value() default "";

    /** Записывать ли отдельный счётчик ошибок. */
    boolean countFailures() default true;
}
