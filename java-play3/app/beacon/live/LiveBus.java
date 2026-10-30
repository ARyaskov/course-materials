package beacon.live;

import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.NotUsed;
import org.apache.pekko.japi.Pair;
import org.apache.pekko.stream.Materializer;
import org.apache.pekko.stream.javadsl.BroadcastHub;
import org.apache.pekko.stream.javadsl.Keep;
import org.apache.pekko.stream.javadsl.MergeHub;
import org.apache.pekko.stream.javadsl.Sink;
import org.apache.pekko.stream.javadsl.Source;

/**
 * Шина живых событий: «многие продюсеры — многие подписчики».
 *
 * <p>{@link MergeHub} даёт {@link Sink}, в который пишут пробы и детектор инцидентов,
 * {@link BroadcastHub} — {@link Source}, из которого читают SSE-соединения и WebSocket-и.
 * Между ними подключён {@code Sink.ignore()}: без единственного постоянного потребителя
 * BroadcastHub выбрасывал бы события, пока нет подписчиков, и первый подключившийся
 * получал бы «хвост» истории.
 */
@Singleton
public class LiveBus {

    private final Materializer materializer;
    private final Sink<LiveEvent, NotUsed> inlet;
    private final Source<LiveEvent, NotUsed> outlet;

    @Inject
    public LiveBus(Materializer materializer) {
        this.materializer = materializer;
        Pair<Sink<LiveEvent, NotUsed>, Source<LiveEvent, NotUsed>> hub =
                MergeHub.of(LiveEvent.class, 64)
                        .toMat(BroadcastHub.of(LiveEvent.class, 256), Keep.both())
                        .run(materializer);
        this.inlet = hub.first();
        this.outlet = hub.second();
        this.outlet.runWith(Sink.ignore(), materializer);
    }

    public void publish(LiveEvent event) {
        Source.single(event).runWith(inlet, materializer);
    }

    /** Поток событий конкретной организации: фильтрация на стороне сервера, а не клиента. */
    public Source<LiveEvent, NotUsed> subscribe(String orgSlug) {
        return outlet.filter(event -> event.orgSlug().equals(orgSlug));
    }
}
