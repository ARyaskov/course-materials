package beacon;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import beacon.domain.Check;
import beacon.domain.ProbeOutcome;
import beacon.domain.ProbeResult;
import beacon.probe.ProbeRunner;
import java.time.Instant;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import play.test.Helpers;

/**
 * Пробы проверяются против настоящего HTTP-сервера: приложение поднимается
 * {@code Helpers.testServer}, и {@link ProbeRunner} опрашивает его собственный /health.
 * Так тест покрывает связку WSClient + сеть + разбор ответа, а не заглушку.
 */
public class ProbeRunnerTest extends BeaconApplicationTest {

    private static final int PORT = 19001;

    private Check check(String path, int expectedStatus, int timeoutMs) {
        return new Check(1L, 1L, "test", "GET", "http://localhost:" + PORT + path,
                expectedStatus, null, timeoutMs, 60, true, Instant.now(), Instant.now());
    }

    @Test
    public void successfulProbeIsUp() throws Exception {
        Helpers.running(Helpers.testServer(PORT, app), () -> {
            try {
                ProbeRunner runner = app.injector().instanceOf(ProbeRunner.class);
                ProbeResult result = runner.run(check("/ready", 200, 5000))
                        .toCompletableFuture().get(10, TimeUnit.SECONDS);

                assertTrue(result.outcome() != ProbeOutcome.DOWN);
                assertEquals(Integer.valueOf(200), result.statusCode());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
    }

    @Test
    public void unexpectedStatusIsDown() throws Exception {
        Helpers.running(Helpers.testServer(PORT, app), () -> {
            try {
                ProbeRunner runner = app.injector().instanceOf(ProbeRunner.class);
                ProbeResult result = runner.run(check("/ready", 204, 5000))
                        .toCompletableFuture().get(10, TimeUnit.SECONDS);

                assertEquals(ProbeOutcome.DOWN, result.outcome());
                assertNotNull(result.error());
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
    }

    @Test
    public void unreachableHostIsDownWithoutStatusCode() throws Exception {
        ProbeRunner runner = app.injector().instanceOf(ProbeRunner.class);
        Check unreachable = new Check(1L, 1L, "test", "GET", "http://localhost:1/nowhere",
                200, null, 2000, 60, true, Instant.now(), Instant.now());

        ProbeResult result = runner.run(unreachable).toCompletableFuture().get(15, TimeUnit.SECONDS);

        assertEquals(ProbeOutcome.DOWN, result.outcome());
        assertEquals(null, result.statusCode());
    }
}
