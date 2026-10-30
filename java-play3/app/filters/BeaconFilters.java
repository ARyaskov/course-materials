package filters;

import javax.inject.Inject;
import play.filters.cors.CORSFilter;
import play.filters.csrf.CSRFFilter;
import play.filters.gzip.GzipFilter;
import play.filters.headers.SecurityHeadersFilter;
import play.filters.hosts.AllowedHostsFilter;
import play.http.DefaultHttpFilters;

/**
 * Порядок фильтров задан явно и читается сверху вниз, как их проходит запрос.
 *
 * <ol>
 *   <li>{@link RequestIdFilter} — раньше всех, чтобы идентификатор был даже у отказов;
 *   <li>{@link AllowedHostsFilter} — отсекает запросы с чужим Host до всякой работы;
 *   <li>{@link SecurityHeadersFilter}, {@link CORSFilter}, {@link GzipFilter} — правка ответа;
 *   <li>{@link CSRFFilter} — только формы админки, для /api маршруты помечены модификатором nocsrf;
 *   <li>{@link RateLimitFilter} — после аутентификации по ключу невозможен, поэтому считает по IP и ключу;
 *   <li>{@link MetricsFilter} — самым внутренним, чтобы мерить время работы приложения.
 * </ol>
 *
 * <p>Класс подключается строкой {@code play.http.filters = "filters.BeaconFilters"}.
 */
public class BeaconFilters extends DefaultHttpFilters {

    @Inject
    public BeaconFilters(
            RequestIdFilter requestId,
            AllowedHostsFilter allowedHosts,
            SecurityHeadersFilter securityHeaders,
            CORSFilter cors,
            GzipFilter gzip,
            CSRFFilter csrf,
            RateLimitFilter rateLimit,
            MetricsFilter metrics) {
        super(requestId, allowedHosts, securityHeaders, cors, gzip, csrf, rateLimit, metrics);
    }
}
