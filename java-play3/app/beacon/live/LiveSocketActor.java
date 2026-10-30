package beacon.live;

import beacon.metrics.BeaconMetrics;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.HashSet;
import java.util.Set;
import org.apache.pekko.Done;
import org.apache.pekko.actor.AbstractActor;
import org.apache.pekko.actor.ActorRef;
import org.apache.pekko.actor.Props;
import org.apache.pekko.stream.Materializer;
import org.apache.pekko.stream.javadsl.Sink;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.libs.Json;

/**
 * Актор одного WebSocket-соединения.
 *
 * <p>Живёт ровно столько, сколько соединение: {@code ActorFlow} создаёт его на handshake
 * и останавливает при разрыве. В {@code preStart} актор подписывается на шину событий,
 * в {@code postStop} метрика соединений уменьшается — утечки подписок не будет даже
 * при аварийном закрытии.
 */
public class LiveSocketActor extends AbstractActor {

    private static final Logger log = LoggerFactory.getLogger(LiveSocketActor.class);

    private final ActorRef out;
    private final LiveBus liveBus;
    private final Materializer materializer;
    private final BeaconMetrics metrics;
    private final String orgSlug;
    private final Set<String> serviceFilter = new HashSet<>();

    public static Props props(
            ActorRef out, LiveBus liveBus, Materializer materializer, BeaconMetrics metrics, String orgSlug) {
        return Props.create(LiveSocketActor.class,
                () -> new LiveSocketActor(out, liveBus, materializer, metrics, orgSlug));
    }

    private LiveSocketActor(
            ActorRef out, LiveBus liveBus, Materializer materializer, BeaconMetrics metrics, String orgSlug) {
        this.out = out;
        this.liveBus = liveBus;
        this.materializer = materializer;
        this.metrics = metrics;
        this.orgSlug = orgSlug;
    }

    @Override
    public void preStart() {
        metrics.liveConnectionOpened();
        liveBus.subscribe(orgSlug).runWith(
                Sink.actorRef(getSelf(), Done.getInstance()),
                materializer);
    }

    @Override
    public void postStop() {
        metrics.liveConnectionClosed();
    }

    @Override
    public Receive createReceive() {
        return receiveBuilder()
                .match(LiveEvent.class, this::forward)
                .match(JsonNode.class, this::handleCommand)
                .match(Done.class, done -> getContext().stop(getSelf()))
                .build();
    }

    /** Сервер фильтрует события до отправки: клиент не должен получать чужой трафик. */
    private void forward(LiveEvent event) {
        if (!serviceFilter.isEmpty() && !serviceFilter.contains(serviceKeyOf(event))) {
            return;
        }
        out.tell(Json.toJson(event), getSelf());
    }

    private void handleCommand(JsonNode command) {
        String type = command.path("command").asText("");
        switch (type) {
            case "subscribe" -> {
                String service = command.path("service").asText("");
                if (!service.isBlank()) {
                    serviceFilter.add(service);
                }
                out.tell(ack("subscribed", service), getSelf());
            }
            case "unsubscribe" -> {
                serviceFilter.remove(command.path("service").asText(""));
                out.tell(ack("unsubscribed", command.path("service").asText("")), getSelf());
            }
            case "ping" -> out.tell(ack("pong", ""), getSelf());
            default -> {
                log.debug("Неизвестная команда WebSocket: {}", type);
                out.tell(ack("error", "неизвестная команда"), getSelf());
            }
        }
    }

    private static String serviceKeyOf(LiveEvent event) {
        return switch (event) {
            case LiveEvent.ProbeRecorded probe -> probe.serviceKey();
            case LiveEvent.IncidentOpened opened -> opened.serviceKey();
            case LiveEvent.IncidentResolved resolved -> resolved.serviceKey();
            case LiveEvent.Heartbeat ignored -> "";
        };
    }

    private static JsonNode ack(String type, String detail) {
        var node = Json.newObject();
        node.put("type", type);
        node.put("detail", detail);
        return node;
    }
}
