package controllers;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static play.test.Helpers.GET;
import static play.test.Helpers.POST;
import static play.test.Helpers.contentAsString;
import static play.test.Helpers.route;

import beacon.BeaconApplicationTest;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;
import play.libs.Json;
import play.mvc.Http;
import play.mvc.Result;
import play.test.Helpers;

/** Данные организации demo приходят из эволюции 4.sql, поэтому фикстуры не нужны. */
public class StatusApiControllerTest extends BeaconApplicationTest {

    private static final String DEMO_KEY = "beacon_demo.0123456789abcdef0123456789abcdef";

    @Test
    public void publicStatusIsAvailableWithoutApiKey() {
        Result result = route(app, Helpers.fakeRequest(GET, "/api/v1/status/demo"));

        assertEquals(Http.Status.OK, result.status());
        JsonNode body = Json.parse(contentAsString(result));
        assertEquals("demo", body.get("org").asText());
        assertTrue(body.get("services").isArray());
    }

    @Test
    public void privateEndpointRequiresApiKey() {
        Result result = route(app, Helpers.fakeRequest(GET, "/api/v1/orgs/demo/services"));

        assertEquals(Http.Status.UNAUTHORIZED, result.status());
        assertTrue(result.header("WWW-Authenticate").isPresent());
    }

    @Test
    public void validApiKeyOpensPrivateEndpoint() {
        Result result = route(app, Helpers.fakeRequest(GET, "/api/v1/orgs/demo/services")
                .header("Authorization", "Bearer " + DEMO_KEY));

        assertEquals(Http.Status.OK, result.status());
        assertTrue(contentAsString(result).contains("\"key\":\"api\""));
    }

    @Test
    public void keyOfAnotherOrganizationIsForbidden() {
        Result result = route(app, Helpers.fakeRequest(GET, "/api/v1/orgs/other/services")
                .header("Authorization", "Bearer " + DEMO_KEY));

        assertEquals(Http.Status.FORBIDDEN, result.status());
    }

    @Test
    public void invalidPayloadReturnsUnprocessableEntity() {
        JsonNode body = Json.newObject().put("name", "no url here");

        Result result = route(app, Helpers.fakeRequest(POST, "/api/v1/orgs/demo/checks")
                .header("Authorization", "Bearer " + DEMO_KEY)
                .bodyJson(body));

        assertEquals(Http.Status.UNPROCESSABLE_ENTITY, result.status());
        assertTrue(contentAsString(result).contains("validation_failed"));
    }

    @Test
    public void unknownRouteReturnsJsonErrorUnderApiPrefix() {
        Result result = route(app, Helpers.fakeRequest(GET, "/api/v1/nope"));

        assertEquals(Http.Status.NOT_FOUND, result.status());
        assertTrue(contentAsString(result).contains("not_found"));
    }
}
