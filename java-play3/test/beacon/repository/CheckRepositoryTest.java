package beacon.repository;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import beacon.BeaconApplicationTest;
import beacon.domain.Check;
import beacon.domain.CheckContext;
import beacon.domain.ProbeOutcome;
import beacon.domain.ProbeResult;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.Test;

/**
 * Репозитории проверяются на настоящих эволюциях: если миграция не применяется на H2,
 * тест падает раньше, чем это заметят на стенде.
 */
public class CheckRepositoryTest extends BeaconApplicationTest {

    private <T> T await(java.util.concurrent.CompletionStage<T> stage) throws Exception {
        return stage.toCompletableFuture().get(10, TimeUnit.SECONDS);
    }

    @Test
    public void claimDueReturnsChecksAndShiftsNextRun() throws Exception {
        CheckRepository checks = app.injector().instanceOf(CheckRepository.class);

        List<CheckContext> first = await(checks.claimDue(Instant.now().plusSeconds(60), 10));
        assertFalse("демо-эволюция создаёт две проверки", first.isEmpty());

        // Повторный вызов на то же время не должен вернуть те же проверки:
        // claimDue сдвинул next_run_at внутри той же транзакции.
        List<CheckContext> second = await(checks.claimDue(Instant.now(), 10));
        assertTrue(second.isEmpty());
    }

    @Test
    public void importSkipsDuplicatesByUrl() throws Exception {
        CheckRepository checks = app.injector().instanceOf(CheckRepository.class);
        ServiceRepository services = app.injector().instanceOf(ServiceRepository.class);

        long serviceId = await(services.listByOrgSlug("demo")).get(0).id();
        Check candidate = new Check(0L, serviceId, "imported", "GET",
                "http://localhost:9000/imported", 200, null, 5000, 60, true, Instant.now(), Instant.now());

        assertEquals(1, (int) await(checks.importAll(serviceId, List.of(candidate))));
        assertEquals(0, (int) await(checks.importAll(serviceId, List.of(candidate))));
    }

    @Test
    public void probeResultsFeedDailyRollup() throws Exception {
        CheckRepository checks = app.injector().instanceOf(CheckRepository.class);
        ProbeResultRepository results = app.injector().instanceOf(ProbeResultRepository.class);

        long checkId = await(checks.listByOrgSlug("demo")).get(0).id();
        await(results.save(ProbeResult.unsaved(checkId, Instant.now(), 120, 200, ProbeOutcome.UP, null)));
        await(results.save(ProbeResult.unsaved(checkId, Instant.now(), 900, 500, ProbeOutcome.DOWN, "boom")));

        assertEquals(List.of(ProbeOutcome.DOWN, ProbeOutcome.UP), await(results.recentOutcomes(checkId, 2)));

        var history = await(results.history(checkId, 1));
        assertEquals(1, history.size());
        assertEquals(2, history.get(0).totalCount());
        assertEquals(1, history.get(0).upCount());
    }

    @Test
    public void p95IsComputedWithoutWindowFunctions() throws Exception {
        CheckRepository checks = app.injector().instanceOf(CheckRepository.class);
        ProbeResultRepository results = app.injector().instanceOf(ProbeResultRepository.class);

        long checkId = await(checks.listByOrgSlug("demo")).get(1).id();
        for (int i = 1; i <= 100; i++) {
            await(results.save(ProbeResult.unsaved(
                    checkId, Instant.now(), i, 200, ProbeOutcome.UP, null)));
        }

        long p95 = await(results.p95Duration(checkId, Instant.now().minusSeconds(3600)));
        assertTrue("p95 должен попасть в верхний хвост, получено " + p95, p95 >= 90 && p95 <= 100);
    }
}
