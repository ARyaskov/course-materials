package io.meterway.quota;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;

class QuotaWindowTest {

    @Test
    @DisplayName("Минутное окно усекается до начала минуты")
    void truncatesToMinute() {
        Instant moment = Instant.parse("2026-05-01T10:37:42.512Z");
        assertEquals(Instant.parse("2026-05-01T10:37:00Z"), QuotaWindow.MINUTE.windowStart(moment));
        // 17.488 секунды до сброса округляются вверх: Retry-After: 17 привёл бы к новому 429
        assertEquals(18L, QuotaWindow.MINUTE.secondsUntilReset(moment));
    }

    @Test
    @DisplayName("Месячное окно начинается первым числом, а не 30 днями назад")
    void monthStartsOnFirstDay() {
        Instant moment = Instant.parse("2026-05-17T10:00:00Z");
        assertEquals(Instant.parse("2026-05-01T00:00:00Z"), QuotaWindow.MONTH.windowStart(moment));
        assertEquals(Instant.parse("2026-06-01T00:00:00Z"), QuotaWindow.MONTH.windowEnd(moment));
    }
}
