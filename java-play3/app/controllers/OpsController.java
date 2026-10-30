package controllers;

import beacon.db.DatabaseExecutionContext;
import beacon.metrics.BeaconMetrics;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import play.db.Database;
import play.libs.Json;
import play.mvc.Controller;
import play.mvc.Result;

/**
 * Эксплуатационные эндпоинты.
 *
 * <p>{@code /ready} отвечает без обращения к зависимостям — это признак «процесс жив».
 * {@code /health} действительно ходит в базу: по нему оркестратор понимает, что инстанс
 * способен обслуживать запросы. Разделение важно: иначе кратковременная недоступность
 * БД перезапускает все поды разом.
 */
@Singleton
public class OpsController extends Controller {

    private final Database db;
    private final DatabaseExecutionContext dbExecutionContext;
    private final BeaconMetrics registry;

    @Inject
    public OpsController(Database db, DatabaseExecutionContext dbExecutionContext, BeaconMetrics registry) {
        this.db = db;
        this.dbExecutionContext = dbExecutionContext;
        this.registry = registry;
    }

    public CompletionStage<Result> health() {
        return CompletableFuture.supplyAsync(() -> db.withConnection(connection -> {
            try (var st = connection.prepareStatement("SELECT 1")) {
                try (var rs = st.executeQuery()) {
                    return rs.next();
                }
            }
        }), dbExecutionContext)
                .thenApply(alive -> {
                    var body = Json.newObject();
                    body.put("status", alive ? "ok" : "degraded");
                    body.put("database", alive ? "up" : "down");
                    return alive ? ok(body) : status(SERVICE_UNAVAILABLE, body);
                })
                .exceptionally(error -> {
                    var body = Json.newObject();
                    body.put("status", "degraded");
                    body.put("database", "down");
                    body.put("error", error.getMessage());
                    return status(SERVICE_UNAVAILABLE, body);
                });
    }

    public Result ready() {
        var body = Json.newObject();
        body.put("status", "ready");
        return ok(body);
    }

    public Result metrics() {
        return ok(registry.render()).as("text/plain; version=0.0.4; charset=utf-8");
    }
}
