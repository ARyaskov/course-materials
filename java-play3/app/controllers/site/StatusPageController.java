package controllers.site;

import beacon.config.BeaconSettings;
import beacon.domain.Organization;
import beacon.domain.ServiceStatus;
import beacon.domain.TimeRange;
import beacon.repository.CheckRepository;
import beacon.repository.IncidentRepository;
import beacon.repository.OrganizationRepository;
import beacon.repository.ProbeResultRepository;
import beacon.status.StatusService;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CompletionStage;
import javax.inject.Inject;
import javax.inject.Singleton;
import org.apache.pekko.stream.javadsl.Source;
import org.apache.pekko.util.ByteString;
import play.i18n.Lang;
import play.libs.Scala;
import play.i18n.MessagesApi;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

/**
 * Публичная статус-страница.
 *
 * <p>Один и тот же ресурс отдаётся в трёх представлениях: HTML для людей,
 * JSON для интеграций (см. {@code controllers.api.StatusApiController}) и CSV потоком
 * для выгрузки. Выбор делает content negotiation, а не отдельные URL с расширениями.
 */
@Singleton
public class StatusPageController extends Controller {

    private final OrganizationRepository organizations;
    private final StatusService statusService;
    private final IncidentRepository incidents;
    private final CheckRepository checks;
    private final ProbeResultRepository results;
    private final MessagesApi messagesApi;
    private final BeaconSettings settings;

    @Inject
    public StatusPageController(
            OrganizationRepository organizations,
            StatusService statusService,
            IncidentRepository incidents,
            CheckRepository checks,
            ProbeResultRepository results,
            MessagesApi messagesApi,
            BeaconSettings settings) {
        this.organizations = organizations;
        this.statusService = statusService;
        this.incidents = incidents;
        this.checks = checks;
        this.results = results;
        this.messagesApi = messagesApi;
        this.settings = settings;
    }

    public CompletionStage<Result> index(Http.Request request) {
        return organizations.listAll().thenApply(list ->
                ok(views.html.index.render(Scala.asScala(list), request, messagesApi.preferred(request))));
    }

    public CompletionStage<Result> show(String slug, Http.Request request) {
        return organizations.findBySlug(slug).thenCompose(found -> {
            if (found.isEmpty()) {
                return notFoundPage(request);
            }
            Organization org = found.get();
            return statusService.statusOf(slug).thenApply(statuses -> {
                if (request.accepts(Http.MimeTypes.HTML)) {
                    return ok(views.html.status.render(
                            org, Scala.asScala(statuses), settings.statusPage().historyDays(),
                            request, messagesApi.preferred(request)));
                }
                return ok(play.libs.Json.toJson(
                        statuses.stream().map(beacon.api.Views.ServiceStatusView::of).toList()));
            });
        });
    }

    public CompletionStage<Result> incidents(String slug, int page, Http.Request request) {
        int pageSize = 20;
        int offset = Math.max(0, page - 1) * pageSize;
        return organizations.findBySlug(slug).thenCompose(found -> {
            if (found.isEmpty()) {
                return notFoundPage(request);
            }
            return incidents.listByOrgSlug(slug, false, pageSize, offset).thenApply(list ->
                    ok(views.html.incidents.render(
                            found.get(), Scala.asScala(list), page, request, messagesApi.preferred(request))));
        });
    }

    /**
     * Выгрузка результатов проб. Ответ строится потоком: выборка может быть большой,
     * а держать её целиком в памяти незачем.
     */
    public CompletionStage<Result> exportCsv(String slug, TimeRange range) {
        Instant from = range.from(Instant.now());
        return checks.listByOrgSlug(slug).thenCompose(list -> {
            List<Long> ids = list.stream().map(beacon.domain.Check::id).toList();
            if (ids.isEmpty()) {
                return java.util.concurrent.CompletableFuture.completedFuture(
                        ok("check_id,started_at,duration_ms,status_code,outcome\n").as("text/csv"));
            }
            Source<ByteString, ?> body = Source.from(ids)
                    .mapAsync(4, id -> results.listByCheck(id, from, 5000))
                    .mapConcat(rows -> rows)
                    .map(row -> ByteString.fromString("%d,%s,%d,%s,%s\n".formatted(
                            row.checkId(), row.startedAt(), row.durationMs(),
                            row.statusCode() == null ? "" : row.statusCode(),
                            row.outcome().name())))
                    .prepend(Source.single(ByteString.fromString(
                            "check_id,started_at,duration_ms,status_code,outcome\n")));

            return java.util.concurrent.CompletableFuture.completedFuture(
                    ok().chunked(body)
                            .as("text/csv; charset=utf-8")
                            .withHeader("Content-Disposition",
                                    "attachment; filename=\"beacon-%s-%s.csv\"".formatted(slug, range)));
        });
    }

    /** Переключение языка: Play хранит выбор в cookie PLAY_LANG. */
    public Result switchLang(String code, Http.Request request) {
        String referer = request.header(Http.HeaderNames.REFERER).orElse("/");
        return redirect(referer).withLang(Lang.forCode(code), messagesApi);
    }

    private CompletionStage<Result> notFoundPage(Http.Request request) {
        return java.util.concurrent.CompletableFuture.completedFuture(
                notFound(views.html.error.render(404, "организация не найдена", "-")));
    }
}
