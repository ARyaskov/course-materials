package io.meterway.metering;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TimeOrderedUuidTest {

    @Test
    @DisplayName("Версия 7 и вариант RFC 4122")
    void hasCorrectVersionAndVariant() {
        UUID uuid = TimeOrderedUuid.from(1_777_000_000_000L);
        assertEquals(7, uuid.version());
        assertEquals(2, uuid.variant());
    }

    @Test
    @DisplayName("Более позднее время даёт лексикографически больший идентификатор")
    void ordersByTime() {
        UUID earlier = TimeOrderedUuid.from(1_777_000_000_000L);
        UUID later = TimeOrderedUuid.from(1_777_000_001_000L);
        assertTrue(earlier.toString().compareTo(later.toString()) < 0);
    }
}
