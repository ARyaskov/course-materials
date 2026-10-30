package io.meterway.metering;

import java.security.SecureRandom;
import java.time.Clock;
import java.util.UUID;

/**
 * UUID версии 7: старшие 48 бит — миллисекунды Unix-времени.
 * Случайный UUIDv4 в секционированной таблице раскидывает вставки по всему B-дереву индекса;
 * время-упорядоченный держит их в конце, что заметно на сотнях тысяч событий в минуту.
 */
public final class TimeOrderedUuid {

    private static final SecureRandom RANDOM = new SecureRandom();

    private TimeOrderedUuid() {
    }

    public static UUID next(Clock clock) {
        return from(clock.millis());
    }

    public static UUID from(long epochMillis) {
        byte[] bytes = new byte[10];
        RANDOM.nextBytes(bytes);

        long high = (epochMillis & 0xFFFF_FFFF_FFFFL) << 16
                | 0x7000L
                | (bytes[0] & 0x0FL) << 8
                | (bytes[1] & 0xFFL);

        long low = 0x8000_0000_0000_0000L;
        for (int i = 2; i < 10; i++) {
            low |= (bytes[i] & 0xFFL) << (8 * (9 - i));
        }
        low &= 0xBFFF_FFFF_FFFF_FFFFL;
        low |= 0x8000_0000_0000_0000L;

        return new UUID(high, low);
    }
}
