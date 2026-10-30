package filters;

import beacon.metrics.BeaconMetrics;
import java.util.concurrent.CompletionStage;
import java.util.function.Function;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.stream.Materializer;
import play.mvc.Filter;
import play.mvc.Http;
import play.mvc.Result;

/** Длительность и коды ответов. Ставится последним, чтобы мерить работу всех остальных фильтров. */
@Singleton
public class MetricsFilter extends Filter {

    private final BeaconMetrics metrics;

    @Inject
    public MetricsFilter(Materializer materializer, BeaconMetrics metrics) {
        super(materializer);
        this.metrics = metrics;
    }

    @Override
    public CompletionStage<Result> apply(
            Function<Http.RequestHeader, CompletionStage<Result>> next, Http.RequestHeader request) {
        long started = System.nanoTime();
        return next.apply(request).thenApply(result -> {
            long durationMs = (System.nanoTime() - started) / 1_000_000L;
            metrics.observeHttp(request.method(), result.status(), durationMs);
            return result;
        });
    }
}
