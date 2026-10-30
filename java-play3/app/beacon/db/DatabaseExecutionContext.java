package beacon.db;

import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.actor.ActorSystem;
import play.libs.concurrent.CustomExecutionContext;

/**
 * Пул для блокирующих JDBC-вызовов.
 *
 * <p>Дефолтный диспетчер Pekko обслуживает HTTP-запросы: занять его ожиданием ответа
 * от PostgreSQL — самый быстрый способ получить таймауты при почти нулевом CPU.
 * Размер {@code beacon-jdbc-dispatcher} согласован с {@code db.default.hikaricp.maximumPoolSize}.
 */
@Singleton
public class DatabaseExecutionContext extends CustomExecutionContext {

    @Inject
    public DatabaseExecutionContext(ActorSystem actorSystem) {
        super(actorSystem, "beacon-jdbc-dispatcher");
    }
}
