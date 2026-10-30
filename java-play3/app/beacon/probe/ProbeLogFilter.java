package beacon.probe;

import beacon.domain.Check;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import play.libs.ws.WSRequestExecutor;
import play.libs.ws.WSRequestFilter;

/**
 * Фильтр исходящих запросов: точка, где удобно вешать логи, метрики и трассировку,
 * не трогая код, который формирует запрос.
 */
public class ProbeLogFilter implements WSRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ProbeLogFilter.class);

    private final Check check;

    public ProbeLogFilter(Check check) {
        this.check = check;
    }

    @Override
    public WSRequestExecutor apply(WSRequestExecutor executor) {
        return request -> {
            long started = System.nanoTime();
            log.debug("--> {} {} (check {})", request.getMethod(), request.getUrl(), check.id());
            return executor.apply(request).whenComplete((response, error) -> {
                long ms = (System.nanoTime() - started) / 1_000_000L;
                if (error == null) {
                    log.debug("<-- {} {} за {} мс", response.getStatus(), request.getUrl(), ms);
                } else {
                    log.debug("<-- ошибка {} за {} мс", request.getUrl(), ms);
                }
            });
        };
    }
}
