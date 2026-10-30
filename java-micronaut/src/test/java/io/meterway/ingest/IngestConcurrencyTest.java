package io.meterway.ingest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.test.StepVerifier;

import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Предел параллелизма потокового приёма.
 * <p>
 * Без второго аргумента {@code flatMap} умолчание Reactor равно 256, и пятьсот событий дали бы
 * 256 одновременных обращений к базе при пуле на двадцать соединений.
 */
class IngestConcurrencyTest {

    private static final int LIMIT = 16;

    @Test
    @DisplayName("Потоковый приём не превышает заданный предел параллелизма")
    void respectsConcurrencyLimit() {
        AtomicInteger concurrent = new AtomicInteger();
        AtomicInteger peak = new AtomicInteger();

        Flux<Integer> processed = Flux.range(1, 500)
                .flatMap(i -> Mono.fromCallable(() -> {
                            peak.accumulateAndGet(concurrent.incrementAndGet(), Math::max);
                            Thread.sleep(2);
                            concurrent.decrementAndGet();
                            return i;
                        }).subscribeOn(Schedulers.boundedElastic()),
                        LIMIT);

        StepVerifier.create(processed).expectNextCount(500).verifyComplete();

        assertTrue(peak.get() <= LIMIT, "предел параллелизма нарушен: " + peak.get());
    }

    @Test
    @DisplayName("Без явного предела параллелизм заметно выше")
    void defaultConcurrencyIsMuchHigher() {
        AtomicInteger concurrent = new AtomicInteger();
        AtomicInteger peak = new AtomicInteger();

        Flux<Integer> processed = Flux.range(1, 500)
                .flatMap(i -> Mono.fromCallable(() -> {
                    peak.accumulateAndGet(concurrent.incrementAndGet(), Math::max);
                    Thread.sleep(2);
                    concurrent.decrementAndGet();
                    return i;
                }).subscribeOn(Schedulers.boundedElastic()));

        StepVerifier.create(processed).expectNextCount(500).verifyComplete();

        assertTrue(peak.get() > LIMIT,
                "умолчание должно быть выше явного предела, получено " + peak.get());
    }
}
