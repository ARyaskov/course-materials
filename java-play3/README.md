# Beacon — сквозной проект курса «Работа с Play Framework 3 в Java 27»

Платформа мониторинга доступности сервисов: HTTP-проверки по расписанию, автоматические
инциденты, публичная статус-страница с живыми обновлениями, JSON API с ключами,
админка на формах Play и вебхуки подписчикам.

Стек: **Java 27**, **Play Framework 3.0.11** (Pekko HTTP), sbt 1.13, PostgreSQL 16,
Guice 6 (`javax.inject`), Twirl, Play Evolutions, Caffeine.

## Быстрый старт

```bash
docker compose up -d postgres
sbt run
```

Открыть:

| URL | Что это |
| --- | --- |
| http://localhost:9000/ | список организаций |
| http://localhost:9000/s/demo | публичная статус-страница |
| http://localhost:9000/s/demo/live | поток SSE |
| http://localhost:9000/admin | админка (`admin@demo.local` / `beacon-admin`) |
| http://localhost:9000/api/v1/status/demo | публичный JSON-статус |
| http://localhost:9000/health, `/ready`, `/metrics` | эксплуатация |

При первом запросе Play предложит применить эволюции — нажать «Apply this script now».
Без интерактива: `sbt "run -Dplay.evolutions.db.default.autoApply=true"`.

Ключ демо-организации для приватного API:

```bash
curl -H "Authorization: Bearer beacon_demo.0123456789abcdef0123456789abcdef" \
     http://localhost:9000/api/v1/orgs/demo/services
```

## Замечание про Java 27

Play 3.0.11 официально проверен на LTS 11/17/21/25 и при старте печатает предупреждение
о неизвестной версии Java. Байткод собирается с `--release 27`, приложение работает;
предупреждение — информационное, а не ошибка сборки.

## Структура

```
app/
  controllers/           OpsController: /health, /ready, /metrics
    site/                публичные страницы, SSE и WebSocket
    api/                 JSON API с аутентификацией по ключу
    admin/               HTML-формы, сессия, CSRF
  beacon/
    api/                 DTO контракта API v1
    config/              типобезопасная конфигурация (BeaconSettings)
    db/                  DatabaseExecutionContext и помощники JDBC
    domain/              доменные записи, PathBindable/QueryStringBindable
    error/               ApiError и HttpErrorHandler
    forms/               формы play.data с Bean Validation
    incident/            детектор инцидентов
    live/                шина событий, sealed LiveEvent, актор WebSocket
    metrics/             реестр метрик и формат Prometheus
    notify/              вебхуки с подписью и ретраями
    parser/              свой BodyParser для CSV-импорта
    probe/               планировщик и исполнитель проб на WSClient
    repository/          репозитории на play.db.Database
    security/            API-ключи, сессия админки, action composition
    status/              агрегация статуса с кэшем
  filters/               RequestId, Metrics, RateLimit, порядок фильтров
  modules/               модули Guice
  views/                 Twirl: публичные страницы, админка, текстовый шаблон письма
conf/
  routes, api.routes, admin.routes, site.routes
  application.conf, application.prod.conf, logback.xml
  messages, messages.ru
  evolutions/default/1.sql … 4.sql
public/                  CSS и JS статус-страницы
test/                    JUnit 4 + play-test
```

## Артефакты по главам

| Глава | Что добавляется в проект |
| --- | --- |
| 1. Устройство Play | `build.sbt`, `project/plugins.sbt`, `project/build.properties`, `conf/application.conf`, `app/controllers/OpsController.java` |
| 2. Маршрутизация | `conf/routes`, `conf/api.routes`, `conf/admin.routes`, `conf/site.routes`, `app/beacon/domain/ServiceKey.java`, `app/beacon/domain/TimeRange.java` |
| 3. Контроллеры и Result | `app/controllers/site/StatusPageController.java`, `app/beacon/security/SecurityKeys.java`, `app/controllers/api/ApiSupport.java` |
| 4. BodyParser | `app/beacon/parser/CsvCheckParser.java`, `app/beacon/parser/CheckImport.java`, `app/controllers/admin/ChecksAdminController.java` |
| 5. JSON и валидация | `app/beacon/api/Views.java`, `app/beacon/api/CreateCheckRequest.java`, `app/beacon/error/ApiError.java` |
| 6. Конфигурация и DI | `app/beacon/config/BeaconSettings.java`, `app/modules/RepositoryModule.java`, `app/modules/ProbeModule.java`, `app/modules/SecurityModule.java` |
| 7. Асинхронность и Pekko | `app/beacon/db/DatabaseExecutionContext.java`, `app/beacon/probe/ProbeExecutionContext.java`, `app/beacon/probe/ProbeScheduler.java` |
| 8. База данных | `conf/evolutions/default/1.sql`…`4.sql`, `app/beacon/db/Rows.java`, `app/beacon/repository/*.java` |
| 9. Play WS | `app/beacon/probe/ProbeRunner.java`, `app/beacon/probe/ProbeLogFilter.java`, `app/beacon/notify/WebhookNotifier.java` |
| 10. Pekko Streams | `app/beacon/live/LiveBus.java`, `app/beacon/live/LiveEvent.java`, потоковый CSV в `StatusPageController` |
| 11. WebSocket | `app/controllers/site/LiveController.java`, `app/beacon/live/LiveSocketActor.java`, `public/javascripts/beacon.js` |
| 12. Twirl и i18n | `app/views/**`, `conf/messages`, `conf/messages.ru`, `public/stylesheets/beacon.css` |
| 13. Фильтры и безопасность | `app/filters/*.java`, `app/beacon/security/ApiKeyService.java`, `ApiKeyAction.java`, `AdminAuthAction.java`, `PasswordHasher.java` |
| 14. Ошибки, кэш, метрики | `app/beacon/error/BeaconErrorHandler.java`, `app/beacon/status/StatusService.java`, `app/beacon/metrics/BeaconMetrics.java` |
| 15. Тесты и эксплуатация | `test/**`, `docker-compose.yml`, `conf/application.prod.conf`, `dist/conf/application.ini`, секция Docker в `build.sbt` |

## Тесты

```bash
sbt test
```

Тесты поднимают приложение на H2 в памяти (`MODE=PostgreSQL`), применяют те же эволюции
и опрашивают собственный HTTP-сервер через `Helpers.testServer`.

Две особенности тестовой конфигурации, без которых тесты не работают:

- `play.filters.hosts.allowed = ["."]` — `Helpers.fakeRequest` не проставляет заголовок `Host`,
  и `AllowedHostsFilter` иначе отвечает `400`;
- эволюции применяются явным обращением к `ApplicationEvolutions` в `@Before`: полагаться
  на порядок инициализации eager-биндингов в тестовом приложении не стоит.

## Сборка и запуск в контейнере

```bash
sbt Docker/publishLocal
docker compose up -d
```

Прод-конфигурация подключается через `-Dconfig.resource=application.prod.conf`
(см. `JAVA_OPTS` в `docker-compose.yml`). Обязательные переменные окружения:
`APPLICATION_SECRET`, `BEACON_DB_URL`, `BEACON_DB_USER`, `BEACON_DB_PASSWORD`,
`BEACON_PUBLIC_HOST`.

## Эксплуатационные заметки

- Эволюции в проде применяются осознанно: `EVOLUTIONS_AUTO_APPLY=true` включает
  автоприменение, `useLocks = true` защищает от гонки нескольких инстансов.
- Блокирующий JDBC живёт в `beacon-jdbc-dispatcher`, исходящие пробы —
  в `beacon-probe-dispatcher`; дефолтный пул Pekko занят только обслуживанием HTTP.
- Планировщик не запускает новый цикл, пока не завершился предыдущий, и считает
  пропущенные тики в метрике `beacon_scheduler_skipped_ticks_total`.
- SSE-поток исключён из gzip-фильтра: сжатие ломает построчную доставку событий.
- Колонка агрегатов называется `day_utc`, а не `day`: `DAY` — зарезервированное слово в H2,
  и на нём падала бы вторая эволюция при запуске тестов.
- Каждому файлу маршрутов соответствует свой пакет контроллеров (`controllers`,
  `controllers.site`, `controllers.api`, `controllers.admin`). Иначе Play перезаписывает
  сгенерированные обратные маршруты и часть из них исчезает.
