package io.meterway.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.YearMonth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BillingPeriodTest {

    @Test
    @DisplayName("Период — полуинтервал: последняя миллисекунда месяца внутри, полночь следующего снаружи")
    void isHalfOpen() {
        BillingPeriod january = BillingPeriod.ofMonth(YearMonth.of(2026, 1));

        assertTrue(january.contains(Instant.parse("2026-01-01T00:00:00Z")));
        assertTrue(january.contains(Instant.parse("2026-01-31T23:59:59.999Z")));
        assertFalse(january.contains(Instant.parse("2026-02-01T00:00:00Z")));
    }

    @Test
    @DisplayName("Событие относится к периоду по времени возникновения, а не приёма")
    void derivesPeriodFromOccurrence() {
        BillingPeriod period = BillingPeriod.monthOf(Instant.parse("2026-03-15T12:00:00Z"));
        assertEquals("2026-03", period.label());
        assertEquals(Instant.parse("2026-03-01T00:00:00Z"), period.start());
        assertEquals(Instant.parse("2026-04-01T00:00:00Z"), period.end());
    }
}
