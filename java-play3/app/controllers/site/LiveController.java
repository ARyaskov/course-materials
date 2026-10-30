package controllers.site;

import beacon.live.LiveBus;
import beacon.live.LiveEvent;
import beacon.live.LiveSocketActor;
import beacon.metrics.BeaconMetrics;
import beacon.repository.OrganizationRepository;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.actor.ActorSystem;
import org.apache.pekko.stream.Materializer;
import org.apache.pekko.stream.javadsl.Flow;
import org.apache.pekko.stream.javadsl.Source;
import play.libs.EventSource;
import play.libs.F;
import play.libs.Json;
import play.libs.streams.ActorFlow;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;
import play.mvc.WebSocket;

/**
 * Живые обновления статуса: SSE для страницы и WebSocket для дашборда.
 *
 * <p>SSE проще: односторонний поток, автоматическое переподключение браузером,
 * работает через обычный HTTP. WebSocket нужен там, где клиент отправляет команды —
 * например, подписывается на конкретный сервис.
 */
@Singleton
public class LiveController extends Controller {

    private static final String EVENT_STREAM = "text/event-stream";

    private final LiveBus liveBus;
    private final OrganizationRepository organizations;
    private final ActorSystem actorSystem;
    private final Materializer materializer;
    private final BeaconMetrics metrics;

    @Inject
    public LiveController(
            LiveBus liveBus,
            OrganizationRepository organizations,
            ActorSystem actorSystem,
            Materializer materializer,
            BeaconMetrics metrics) {
        this.liveBus = liveBus;
        this.organizations = organizations;
        this.actorSystem = actorSystem;
        this.materializer = materializer;
        this.metrics = metrics;
    }

    /**
     * SSE-поток. keepAlive шлёт событие раз в 15 секунд: без трафика прокси и балансировщики
     * рвут «молчащее» соединение, а браузер потом переподключается лавиной.
     */
    public CompletionStage<Result> stream(String slug, Http.Request request) {
        return organizations.findBySlug(slug).thenApply(found -> {
            if (found.isEmpty()) {
                return notFound();
            }
            Source<EventSource.Event, ?> events = liveBus.subscribe(slug)
                    .map(event -> EventSource.Event
                            .event(Json.toJson(event))
                            .withName(eventName(event)))
                    .keepAlive(Duration.ofSeconds(15),
                            () -> EventSource.Event
                                    .event(Json.toJson(new LiveEvent.Heartbeat(slug, Instant.now())))
                                    .withName("heartbeat"));

            return ok().chunked(events.via(EventSource.flow()))
                    .as(EVENT_STREAM)
                    .withHeader("Cache-Control", "no-cache, no-transform")
                    .withHeader("X-Accel-Buffering", "no");
        });
    }

    /**
     * WebSocket. Проверка организации выполняется до апгрейда: {@code acceptOrResult}
     * позволяет вернуть обычный HTTP-ответ вместо соединения.
     */
    public WebSocket socket(String slug) {
        return WebSocket.Json.acceptOrResult(request ->
                organizations.findBySlug(slug).thenApply(found -> {
                    if (found.isEmpty()) {
                        return F.Either.<Result, Flow<JsonNode, JsonNode, ?>>Left(notFound("нет такой организации"));
                    }
                    Flow<JsonNode, JsonNode, ?> flow = ActorFlow.actorRef(
                            out -> LiveSocketActor.props(out, liveBus, materializer, metrics, slug),
                            actorSystem,
                            materializer);
                    return F.Either.<Result, Flow<JsonNode, JsonNode, ?>>Right(flow);
                }));
    }

    private static String eventName(LiveEvent event) {
        return switch (event) {
            case LiveEvent.ProbeRecorded ignored -> "probe";
            case LiveEvent.IncidentOpened ignored -> "incident_opened";
            case LiveEvent.IncidentResolved ignored -> "incident_resolved";
            case LiveEvent.Heartbeat ignored -> "heartbeat";
        };
    }
}
