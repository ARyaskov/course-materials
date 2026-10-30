package beacon.probe;

import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.actor.ActorSystem;
import play.libs.concurrent.CustomExecutionContext;

/** Диспетчер фоновых проб: их всплеск не должен влиять на обслуживание HTTP-запросов. */
@Singleton
public class ProbeExecutionContext extends CustomExecutionContext {

    @Inject
    public ProbeExecutionContext(ActorSystem actorSystem) {
        super(actorSystem, "beacon-probe-dispatcher");
    }
}
