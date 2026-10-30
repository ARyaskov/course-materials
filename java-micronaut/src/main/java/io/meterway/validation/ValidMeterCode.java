package io.meterway.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

import static java.lang.annotation.ElementType.ANNOTATION_TYPE;
import static java.lang.annotation.ElementType.FIELD;
import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.PARAMETER;
import static java.lang.annotation.ElementType.RECORD_COMPONENT;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

/**
 * Код метрики должен присутствовать в каталоге.
 * <p>
 * {@code @Constraint(validatedBy = {})} с пустым списком — рабочая конструкция Micronaut:
 * реализация приходит отдельным бином {@code ConstraintValidator}, и ей можно внедрять зависимости.
 */
@Documented
@Retention(RUNTIME)
@Target({FIELD, METHOD, PARAMETER, ANNOTATION_TYPE, RECORD_COMPONENT})
@Constraint(validatedBy = {})
public @interface ValidMeterCode {

    String message() default "Метрика {validatedValue} не зарегистрирована";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
