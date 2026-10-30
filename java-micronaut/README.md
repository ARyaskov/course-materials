# Meterway

Платформа учёта потребления и тарификации на **Java 27 + Micronaut 5.1**.

Сквозной проект курса «Работа с фреймворком Micronaut в Java-бекенд разработке».

## Что делает система

Meterway принимает поток событий потребления от чужих сервисов, сводит их в агрегаты,
применяет тарифный план и выставляет счёт за расчётный период. Попутно она следит,
чтобы клиент не вышел за квоту, и уведомляет внешние системы о событиях биллинга.

```
источник событий
      |
      v
POST /v1/usage-events  --> дедупликация --> квота (Redis) --> usage_events (PostgreSQL)
                                                                    |
                                                                    v
                                                          Kafka: meterway.usage-events
                                                                    |
                                                                    v
                                                        инкрементальная агрегация
                                                                    |
                     закрытие периода <-------------------- usage_aggregates
                             |
                             v
                  тарификация --> invoices + invoice_lines --> outbox --> вебхуки
```

Инженерные задачи, вокруг которых построен код:

- идемпотентный приём на высокой частоте без гонки между `select` и `insert`;
- опоздавшие и переупорядоченные события;
- денежная арифметика в минорных единицах без накопления погрешности;
- ступенчатая тарификация с корректными границами ступеней;
- атомарная проверка квоты под конкуренцией (Lua-скрипт в Redis);
- повторяемое закрытие расчётного периода;
- мультитенантная изоляция на уровне запроса и данных;
- холодный старт и потребление памяти для ingest-подов.

## Быстрый старт

Самый короткий путь — не поднимать ничего руками. Micronaut Test Resources сам запустит
PostgreSQL, Redis и Kafka в контейнерах и подставит их адреса:

```bash
./gradlew run
```

Второй вариант — постоянный локальный стенд с демонстрационными данными.
Окружение `dev` подключает `application-dev.properties` с адресами docker compose
и добавляет к миграциям каталог `db/dev` с тенантом, клиентами, тарифом и ключом доступа:

```bash
docker compose up -d postgres redis kafka
MICRONAUT_ENVIRONMENTS=dev ./gradlew run
```

Приложение поднимется на `http://localhost:8080`, служебные эндпоинты — на `8081`.
Старт занимает около 1,3 секунды вместе с миграциями, пулом соединений и подключением к брокеру.

Проверка приёма события (ключ и клиент — из демонстрационных данных окружения `dev`):

```bash
K='mw_dev_0123456789ab.devsecretdevsecretdevsecret'
TS=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)

curl -sS -X POST http://localhost:8080/v1/usage-events \
  -H 'Content-Type: application/json' -H "X-Api-Key: $K" \
  -d "{\"idempotencyKey\":\"demo-1\",\"meterCode\":\"api.requests\",
       \"customerRef\":\"cust-north\",\"occurredAt\":\"$TS\",
       \"quantity\":1,\"properties\":{\"endpoint\":\"/v1/items\"}}"
```

```json
{"outcome":"accepted","idempotencyKey":"demo-1","eventId":"01a07fc3-ceb0-7e02-a784-c19b81f35018"}
```

Тот же запрос повторно вернёт `200` и `duplicate`; тот же ключ с другим количеством — `409`
и `conflict`; событие старше 72 часов — `400` и `rejected`; превышение квоты — `quota-blocked`
с заголовком `Retry-After`. Дата события задаётся относительной, а не фиксированной:
окно приёма опоздавших событий по умолчанию 72 часа.

Полный цикл до счёта:

```bash
TOKEN=$(curl -sS -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"meterway"}' | jq -r .access_token)

curl -sS -X POST "http://localhost:8080/v1/billing/periods/2026-09/close" \
     -H "Authorization: Bearer $TOKEN"

curl -sS "http://localhost:8080/v1/reports/invoices?period=2026-09" \
     -H "Authorization: Bearer $TOKEN" | jq
```

Повторное закрытие того же периода вернёт `alreadyClosed: true` и не выставит второй счёт.

Полезные адреса:

| Адрес | Что там |
| --- | --- |
| `http://localhost:8080/swagger-ui` | сгенерированная спецификация OpenAPI |
| `http://localhost:8081/health` | состояние приложения и индикатор конвейера |
| `http://localhost:8081/prometheus` | метрики |
| `http://localhost:8081/routes` | таблица маршрутов |
| `http://localhost:8080/control-panel` | Micronaut Control Panel (только в `dev`) |

Наблюдаемость поднимается отдельным профилем:

```bash
docker compose --profile observability up -d
```

## Сборка и проверки

```bash
./gradlew build              # компиляция и тесты (Test Resources поднимут контейнеры)
./gradlew test --tests '*Test'
./gradlew nativeCompile      # native-образ, требуется GraalVM 25
./gradlew dockerBuild
```

## Структура

```
src/main/java/io/meterway/
  Application.java
  config/          конфигурация: @ConfigurationProperties, @EachProperty, фабрики
  domain/          value-типы и доменные исключения
  persistence/     сущности @MappedEntity и репозитории Micronaut Data JDBC
  ingest/          приём событий: DTO, сервис, контроллер
  metering/        каталог метрик, агрегация, обслуживание секций
  quota/           квоты в Redis, Lua-скрипты, распределённая блокировка
  rating/          тарифные модели и движок расчёта
  billing/         закрытие периода, счета, отчётность
  security/        API-ключи, JWT, тенант в PropagatedContext
  messaging/       Kafka-продюсер и консьюмер, разбор outbox
  webhook/         декларативный клиент, подпись, повторы доставки
  web/             фильтры и обработчики ошибок RFC 9457
  realtime/        WebSocket-канал живого потребления
  observability/   метрики и health-индикаторы
src/main/resources/
  application.properties, application-dev.properties
  db/migration/    миграции Flyway
  db/dev/          демонстрационные данные окружения dev
  redis/           Lua-скрипты квот
ops/               prometheus.yml, alerts.yml
docker-compose.yml
```

## Артефакты по главам

| Глава | Что появляется в проекте |
| --- | --- |
| 1 | `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `Application.java`, `application.properties` |
| 2 | `config/MeterDefinition.java`, `config/IngestConfiguration.java`, `config/CoreFactory.java`, `metering/MeterCatalog.java` |
| 3 | `ingest/UsageIngestController.java`, `ingest/UsageEventRequest.java`, `web/CorrelationFilter.java` |
| 4 | `ingest/IngestOutcome.java`, `ingest/IngestResponse.java`, `web/MeterwayProblemHandler.java`, `openapi.properties` |
| 5 | `@ExecuteOn` в контроллерах, `security/TenantContextElement.java`, `security/TenantPropagationFilter.java` |
| 6 | `persistence/entity/*`, `persistence/repository/*`, `UsageRollup.java`, `UsageEventSpecifications.java`, `UsageEventFilter.java`, `billing/UsageEventQueryService.java` |
| 7 | `db/migration/V1..V7`, `metering/PartitionMaintenanceJob.java`, `billing/PeriodClosingService.java` |
| 8 | `@Cacheable` в `UsageIngestService` и `RatingEngine`, `observability/Measured*`, `audit/*`, `ratelimit/*`, `db/migration/V8__audit.sql` |
| 9 | `webhook/WebhookClient.java`, `webhook/RetryOnServerError.java`, `webhook/FailureAction.java`, `webhook/WebhookSigner.java`, `webhook/WebhookDispatcher.java`, `src/test/java/io/meterway/webhook/*` |
| 10 | `security/ApiKeyAuthenticationFetcher.java`, `security/ConsoleAuthenticationProvider.java`, `security/TenantClaimsValidator.java`, `security/TenantPropagationFilter.java`, `config/ConsoleUser.java`, `src/test/java/io/meterway/security/SecurityMatrixTest.java` |
| 11 | `quota/QuotaService.java`, `quota/QuotaWindow.java`, `quota/DistributedLock.java`, `cache/CacheInvalidator.java`, `redis/quota-check-and-consume.lua`, `redis/quota-release.lua`, `src/test/java/io/meterway/quota/QuotaConcurrencyTest.java` |
| 12 | `billing/BillingScheduler.java`, `messaging/OutboxPublisher.java`, `metering/PartitionMaintenanceJob.java`, `event/PeriodClosedEvent.java`, `event/DomainEventPublisher.java`, `event/ShutdownState.java` |
| 13 | `messaging/UsageEventProducer.java`, `messaging/UsageAggregationListener.java`, `messaging/UsageEventMessage.java`, `src/test/java/io/meterway/messaging/UsagePipelineIntegrationTest.java` |
| 14 | `src/test/java/io/meterway/**`, `src/test/resources/application-test.properties` |
| 15 | `observability/IngestMetrics.java`, `observability/PipelineHealthIndicator.java`, `observability/OutboxLagGauge.java`, `ops/prometheus.yml`, `ops/alerts.yml`, `logback.xml` |
| 16 | `realtime/UsageStreamSocket.java`, `realtime/UsageUpdate.java`, `src/test/java/io/meterway/realtime/UsageStreamSocketTest.java` |
| 17 | блок `graalvmNative` и `aot` в `build.gradle.kts` |
| 18 | `docker-compose.yml`, `ops/`, конфигурация окружений, `web/ProblemResponse.java` |

## Конфигурация по окружениям

| Файл | Когда активен | Что задаёт |
| --- | --- | --- |
| `application.properties` | всегда | порты, каталог метрик, кэши, тип и диалект БД, параметры Meterway |
| `application-dev.properties` | `MICRONAUT_ENVIRONMENTS=dev` | адреса docker compose, демо-данные, открытая диагностика, ускоренные расписания |
| `application-k8s.properties` | `MICRONAUT_ENVIRONMENTS=k8s` | импорт секретов из configtree, закрытые эндпоинты, OTLP-экспорт |
| `src/test/resources/application-test.properties` | автоматически в тестах | отключённые фоновые задачи, версии образов Test Resources |

Адреса PostgreSQL, Redis и Kafka в базовой конфигурации намеренно отсутствуют: без них
Test Resources подставляет контейнеры, а в проде значения приходят переменными окружения
(`DATASOURCES_DEFAULT_URL`, `REDIS_URI`, `KAFKA_BOOTSTRAP_SERVERS`) или из `configtree`.

## Оговорки

- Демо-ключ доступа и пароль оператора живут только в окружении `dev` и в реальной установке заменяются.
- Kafka в `docker-compose.yml` объявляет `localhost:9092` как advertised listener: стенд рассчитан на запуск приложения на хосте, а не в контейнере.
- Том PostgreSQL монтируется в `/var/lib/postgresql`, а не в `/var/lib/postgresql/data`: в образе `postgres:18` данные лежат в подкаталоге с номером версии, и старый путь монтирования приводит к отказу контейнера при старте.
- Имя секции `meterway.meters.*` — один сегмент без точек; настоящий код метрики задаётся свойством `code`, потому что точка в ключе конфигурации означает вложенность.
- Секции таблицы событий создаются на три месяца вперёд заданием `PartitionMaintenanceJob`; секция `usage_events_default` должна оставаться пустой.
- Полный пересчёт периода использует `UsageAggregateRepository.replace`, а инкрементальная агрегация — `merge`. Подмена одного другим приводит к удвоению объёма в счёте; на это есть регрессионный тест.

## Состояние проверки

Проверено на Java 27 (`27+35`), Gradle 9.6.0, Micronaut Platform 5.1.3:

- `./gradlew build` — успешно, 56 тестов, 0 падений;
- интеграционные тесты поднимают PostgreSQL 18 и Redis 8 через Test Resources;
- `MICRONAUT_ENVIRONMENTS=dev ./gradlew run` — старт за 1,3 с, миграции применены, каталог из 6 метрик;
- сквозной сценарий: приём события, дедупликация, отказ по квоте, агрегация через Kafka, закрытие периода, счёт со строками, запись в outbox.
