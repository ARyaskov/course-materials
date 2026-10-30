package beacon.repository;

import beacon.db.DatabaseExecutionContext;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import play.db.ConnectionCallable;
import play.db.Database;

/**
 * Общая часть репозиториев: работа с JDBC уезжает в отдельный диспетчер, а наружу
 * торчит {@link CompletionStage} — тип, который умеют возвращать контроллеры Play.
 */
public abstract class JdbcRepository {

    protected final Database db;
    protected final DatabaseExecutionContext ec;

    protected JdbcRepository(Database db, DatabaseExecutionContext ec) {
        this.db = db;
        this.ec = ec;
    }

    protected <T> CompletionStage<T> query(ConnectionCallable<T> block) {
        return CompletableFuture.supplyAsync(() -> db.withConnection(block), ec);
    }

    protected <T> CompletionStage<T> transaction(ConnectionCallable<T> block) {
        return CompletableFuture.supplyAsync(() -> db.withTransaction(block), ec);
    }
}
