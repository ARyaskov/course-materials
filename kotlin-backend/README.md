# Atrium

Сквозной проект курса «Kotlin 2.4 для backend-разработчика»: сервис бронирования переговорных
и рабочих мест в сети коворкингов.

## Быстрый старт

Для сборки нужен JDK 25. Gradle 9.7.1 загрузится через включённый в проект wrapper.

```bash
docker compose up -d          # PostgreSQL 18, Kafka 4 (KRaft), Redis 8, OTel Collector
./gradlew :app-spring:bootRun # Spring Boot 4.1 вариант, http://localhost:8080
./gradlew :app-ktor:run       # Ktor 3.5 вариант, http://localhost:8081
```

## Структура

| Модуль | Назначение |
| --- | --- |
| `build-logic/` | convention plugins Gradle: Kotlin, тесты, ktlint/detekt/kover |
| `domain/` | доменные модели, sealed-статусы, ошибки, инварианты; без фреймворков |
| `application/` | use case-ы и порты (репозитории, часы, платёжный шлюз, издатель событий) |
| `infrastructure/` | PostgreSQL (JDBC / Exposed / jOOQ), Flyway, Kafka, Redis, HTTP-клиенты |
| `app-spring/` | Spring Boot 4.1 приложение |
| `app-ktor/` | Ktor 3.5 приложение с тем же API |

Версии — только в `gradle/libs.versions.toml`.

## Артефакты по главам

| Глава | Файлы |
| --- | --- |
| 1 | `compose.yml`, `docker/otel-collector.yaml`, `domain/.../Ids.kt`, `domain/.../Booking.kt` |
| 2 | `settings.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, `gradle/wrapper/`, `build-logic/`, `config/detekt/`, `.editorconfig`, `*/build.gradle.kts` |
| 3 | `domain/`: `TimeSlot.kt`, `Money.kt`, `Room.kt`, `Booking.kt`, `BookingError.kt`, `Extensions.kt`; `application/ports/*`, `ConfirmBooking.kt`, `CreateBooking.kt`; `infrastructure/postgres/BookingRowMapper.kt`; `app-spring/api/BookingDtos.kt`, `BookingMapping.kt` |
| 4 | `application/`: `Page.kt`, `Outcome.kt`, `Measure.kt`, `Retry.kt`, `Transactional.kt`, `RequestContext.kt`, `ports/Transaction.kt`; `domain/Clocked.kt`, `domain/src/testFixtures/*Fixtures.kt`; `infrastructure/cache/CachedLookup.kt`, `CachedRoomRepository.kt`, `json/JsonMapper.kt`, `ids/UuidV7IdGenerator.kt`; `app-ktor/config/Env.kt`, `routes/RoomRoutes.kt`; `docs/decisions.md` |
| 5 | `domain/Checks.kt`, `domain/src/test/TimeSlotTest.kt`; `application/CancelBooking.kt`; `infrastructure/paygate/PayGateClient.kt`; `app-spring/api/ApiErrorHandler.kt`; `app-ktor/api/BookingDto.kt`, `Validation.kt`, `plugins/ErrorPages.kt` |
| 6 | `application/`: `ApplicationScope.kt`, `Cancellation.kt`, `RoomAvailability.kt`, `ExpirePendingBookings.kt`, `OccupancyTracker.kt`, `RoomUtilizationBackfill.kt`, `ports/UtilizationRepository.kt`, `ports/NotificationSender.kt`; `infrastructure/concurrency/Dispatchers.kt`, `notify/NotificationDispatcher.kt` |
| 7 | `app-spring/`: `AtriumApplication.kt`, `application.yaml`, `config/AtriumProperties.kt`, `JacksonConfig.kt`, `PersistenceConfig.kt`, `UseCaseConfig.kt`, `Beans.kt`, `api/RoomController.kt`, `BookingController.kt`, `MemberPrincipal.kt`, тесты `api/*Test.kt`, `config/*Test.kt`, `BookingFlowIntegrationTest.kt`; `application/ListMemberBookings.kt`, `ports/BookingPolicy.kt`, `testFixtures/testing/Fakes.kt`; `infrastructure/paygate/LocalPaymentGateway.kt` |
| 8 | `app-ktor/`: `Application.kt`, `application.yaml`, `config/AtriumConfig.kt`, `di/Dependencies.kt`, `DataSources.kt`, `plugins/Serialization.kt`, `Observability.kt`, `RequestId.kt`, `DevPrincipal.kt`, `Lifecycle.kt`, `Routing.kt`, `ErrorPages.kt`, `routes/BookingRoutes.kt`, `api/Serializers.kt`, тесты `RoomRoutesTest`, `BookingRoutesTest`, `plugins/ErrorPagesTest`, `api/SerializationTest`, `Postgres.kt` |
| 9 | `infrastructure/`: `db/migration/V001__locations_rooms.sql`, `V002__bookings.sql`, `postgres/JdbcTransactionRunner.kt`, `JdbcBookingRepository.kt`, `JdbcRoomRepository.kt`, `SerializationRetry.kt`, `exposed/Tables.kt`, `TstzRangeColumnType.kt`, `ExposedBookingRepository.kt`, `jooq/TimeSlotConverter.kt`, `JooqBookingRepository.kt`, `JooqUtilizationQueries.kt`, `sql/occupancy_by_room.sql`, `src/main/generated/`; `scripts/jooq-codegen.sh`; `app-spring/adapters/BookingEntity.kt`, `JdbcConverters.kt`, `JdbcClientBookingRepository.kt`; `app-spring/src/test/resources/db/testdata/V900__seed_test.sql`, `application-test.yaml`; `application/ports/SlotConflictException`, `OptimisticLockException`, `TransactionRunner.NONE` |
| 10 | `application/ListQuery.kt` (фильтр, сортировка, `Cursor`); `app-spring/config/SecurityConfig.kt`, `MemberPrincipalResolver.kt`, `api/OccupancyController.kt`, `BookingListParams.kt`, `test/api/OpenApiContractTest.kt`; `app-ktor/plugins/Security.kt` (JWT, `withRole`), `routes/OccupancyRoutes.kt`, `api/BookingListParams.kt`; `docs/openapi.yaml` |
| 11 | миграции `V003__outbox.sql`, `V004__processed_events.sql`, `V005__backfill_runs.sql`; `infrastructure/events/` (`BookingEventDto`, `KafkaProducerSender`, `KafkaConsumerLoop`, `ProcessedEventRepository`, `NotificationOutboxRepository`, `BookingEventHandler`), `outbox/OutboxEventPublisher.kt`, `OutboxRelay.kt`, `postgres/JobLease.kt`, `JdbcUtilizationRepository.kt`; `application/ports/BackfillCheckpointRepository.kt`, `RoomUtilizationBackfill.kt`; `app-spring/jobs/*`, `adapters/KafkaBookingEventSender.kt`, `BookingEventListener.kt`, `config/KafkaConfig.kt`; `app-ktor/jobs/Jobs.kt` |
| 12 | `infrastructure/cache/CaffeineRoomCache.kt`, `CachedRoomRepository.kt` (Caffeine), `redis/AtriumRedis`, `RedisRoomCache`, `RedisInvalidation`, `RedisLock`, `RedisRateLimiter`, `resilience/ResilientPaymentGateway.kt`, `idempotency/JdbcIdempotencyStore.kt`, миграция `V006__idempotency_keys.sql`; `application/ports/IdempotencyStore.kt`, `CreateBooking` с `Idempotency-Key`, `Booking.extendHold`, `BookingError.PaymentUnavailable` |
| 13 | `domain/test/BookingTest.kt`, `TimeSlotPropertyTest.kt`, `testFixtures/Arbs.kt`; `application/test/ConfirmBookingTest.kt`, `testFixtures/Scenarios.kt`, `ContractCase.kt`, `resources/contract/v1/*`; `infrastructure/test/postgres/PostgresTest.kt`, `BookingConcurrencyTest.kt`, `MigrationsTest.kt`; `build-logic/atrium.integration-test-conventions.gradle.kts` |
| 14 | `application/ports/Metrics.kt`, `Tracing.kt`; `infrastructure/metrics/MicrometerMetrics.kt`, `tracing/OtelTracing.kt`; `domain/Redacted.kt`; `app-ktor/resources/logback.xml`, `plugins/Tracing.kt`, `Readiness.kt`, `Lifecycle.kt`, `routes/MetricsRoutes.kt`, `di/Telemetry.kt`, `config/AtriumConfig.validate`, `Env.secret`; `app-spring/config/RequestIdFilter.kt`, `ApplicationScopeLifecycle.kt`; `benchmarks/`; `docs/logging.md`, `metrics.md`, `features.md`; `scripts/seed-load.sql` |
| 15 | `docker/Dockerfile.spring`, `Dockerfile.ktor` (multi-stage, layers, CDS, non-root), `docker/postgres/init.sql`, `docker/wiremock/*`, `docker/prometheus.yml`, `docker/k8s/deployment-fragment.yaml`; `compose.yml` (профили `app`, `observability`), `.env.example`, `scripts/dev-up.sh`; `app-ktor/routes/HealthRoutes.kt`, `Application.main --dry-run`; `app-spring/health/*`; `.github/workflows/ci.yml`, `deploy.yml`, `.githooks/pre-commit`; `docs/ci.md`, `docs/startup.md` |
| 16 | `atrium-client/` (`AtriumClient.kt`, `Model.kt`, `Json.kt`, `package-info.java`, `api/atrium-client.api`, `src/test/java/.../JavaCallerTest.java`); `detekt-rules/` (`RunBlockingInProduction`, `SwallowedCancellation`, `DataClassEntity`); `docs/team-guide.md`, `team-guide-cases.md`, `migration-notes.md`, `docs/anti-patterns/*` |
| 17 | `scripts/smoke.sh`; `compose.yml` профиль `worker`; `infrastructure/test/postgres/QueryPlansTest.kt`, `StatementTimeoutTest.kt`; `connection-init-sql` в обоих приложениях; `docs/walkthrough.md`, `docs/checklist.md`, `docs/runbook.md` (backfill, откат) |
