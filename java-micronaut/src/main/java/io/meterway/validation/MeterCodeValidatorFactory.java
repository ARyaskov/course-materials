package io.meterway.validation;

import io.meterway.metering.MeterCatalog;
import io.micronaut.context.annotation.Factory;
import io.micronaut.validation.validator.constraints.ConstraintValidator;
import jakarta.inject.Singleton;

@Factory
public class MeterCodeValidatorFactory {

    /**
     * Валидатор с доступом к каталогу метрик.
     * <p>
     * Проверка на {@code null} внутри — соглашение jakarta.validation: за отсутствие значения
     * отвечает {@code @NotNull}, а ограничение формата к {@code null} относиться не должно.
     * Нарушение этого правила даёт два сообщения об ошибке вместо одного.
     */
    @Singleton
    ConstraintValidator<ValidMeterCode, String> meterCodeValidator(MeterCatalog catalog) {
        return (value, annotationMetadata, context) -> value == null || catalog.contains(value);
    }
}
