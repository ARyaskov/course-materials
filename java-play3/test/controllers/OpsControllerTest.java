package controllers;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static play.test.Helpers.GET;
import static play.test.Helpers.contentAsString;
import static play.test.Helpers.route;

import beacon.BeaconApplicationTest;
import org.junit.Test;
import play.mvc.Http;
import play.mvc.Result;
import play.test.Helpers;

public class OpsControllerTest extends BeaconApplicationTest {

    @Test
    public void readyAnswersWithoutTouchingDatabase() {
        Result result = route(app, Helpers.fakeRequest(GET, "/ready"));

        assertEquals(Http.Status.OK, result.status());
        assertTrue(contentAsString(result).contains("ready"));
    }

    @Test
    public void healthChecksDatabaseConnection() {
        Result result = route(app, Helpers.fakeRequest(GET, "/health"));

        assertEquals(Http.Status.OK, result.status());
        assertTrue(contentAsString(result).contains("\"database\":\"up\""));
    }

    @Test
    public void metricsAreExposedInPrometheusFormat() {
        route(app, Helpers.fakeRequest(GET, "/ready"));
        Result result = route(app, Helpers.fakeRequest(GET, "/metrics"));

        assertEquals(Http.Status.OK, result.status());
        assertTrue(contentAsString(result).contains("beacon_http_requests_total"));
    }

    @Test
    public void everyResponseCarriesRequestId() {
        Result result = route(app, Helpers.fakeRequest(GET, "/ready"));

        assertTrue(result.header("X-Request-Id").isPresent());
    }
}
