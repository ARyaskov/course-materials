package io.meterway.validation;

import io.meterway.ingest.UsageEventRequest;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import io.micronaut.validation.validator.Validator;
import jakarta.inject.Inject;
import jakarta.validation.ConstraintViolation;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@MicronautTest(startApplication = false)
class ValidMeterCodeTest {

    @Inject
    Validator validator;

    private UsageEventRequest event(String meterCode) {
        return new UsageEventRequest("k-1", meterCode, "cust-north",
                Instant.now().minusSeconds(60), BigDecimal.ONE, Map.of());
    }

    @Test
    @DisplayName("Незарегистрированный код метрики не проходит валидацию")
    void rejectsUnknownMeter() {
        Set<ConstraintViolation<UsageEventRequest>> violations = validator.validate(event("api.unknown"));

        assertEquals(1, violations.size());
        assertEquals("meterCode", violations.iterator().next().getPropertyPath().toString());
    }

    @Test
    @DisplayName("Зарегистрированный код проходит")
    void acceptsKnownMeter() {
        assertTrue(validator.validate(event("api.requests")).isEmpty());
    }

    @Test
    @DisplayName("Пустой код даёт одно нарушение, а не два: ограничение не реагирует на null")
    void doesNotDuplicateNullCheck() {
        Set<ConstraintViolation<UsageEventRequest>> violations = validator.validate(event(null));

        assertEquals(1, violations.size(), "@ValidMeterCode не должен добавлять нарушение к @NotBlank");
    }
}
