package dev.atrium.client;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

import static org.junit.jupiter.api.Assertions.assertNotNull;

/** Публичный API с точки зрения Java: если этот файл не компилируется с -Werror — API неудобен (уроки 16.1, 16.5). */
class JavaCallerTest {
    private static final kotlin.uuid.Uuid ROOM = kotlin.uuid.Uuid.Companion.parse("00000000-0000-0000-0000-000000000101");
    private static final Instant START = Instant.parse("2026-10-02T10:00:00Z");

    @Test
    void javaFriendlyApi() throws Exception {
        try (var client = new AtriumClient("http://localhost:8089", "test-key")) {                 // @JvmOverloads
            var request = CreateBookingRequest.builder().roomId(ROOM).startsAt(START).durationMinutes(60).build();
            assertNotNull(request);
            // Сигнатуры существуют и типизированы для Java; сетевой вызов здесь не выполняется
            CompletableFuture<BookingResult> async = client.createBookingAsync(request, "key-1");  // без Continuation
            assertNotNull(async);
            async.cancel(true);
            List<UUID> ignored = List.of();
            assertNotNull(ignored);
            assertNotNull(AtriumClient.DEFAULT_TIMEOUT);                                          // @JvmField
        }
    }

    static String describe(BookingResult result) {
        return switch (result) {                                                                   // sealed → исчерпывающий switch
            case BookingResult.Created c -> "created " + c.getBooking().getId();
            case BookingResult.Rejected r -> "rejected " + r.getProblem().getType();
        };
    }
}
