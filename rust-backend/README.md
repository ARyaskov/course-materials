# CourseFlow API

Сквозной проект курса «Rust Backend Developer 2026: Axum, SQLx, PostgreSQL». Backend платформы
онлайн-курсов: пользователи трёх ролей, курсы и уроки, покупка доступа через платёжного
провайдера (в workspace есть его имитация `billing-mock`), enrollment, прогресс и сертификаты,
уведомления в реальном времени по WebSocket и SSE.

Стек: Rust 1.98 (Edition 2024), Axum 0.8, Tokio 1.53, SQLx 0.9 + PostgreSQL 18, Redis 8
(redis-rs 1.7), reqwest 0.13, jsonwebtoken 11, argon2 0.6, tower-http 0.7, utoipa 5,
tracing + metrics/Prometheus, Docker multi-stage с cargo-chef, GitHub Actions.

## Быстрый старт

```bash
cp .env.example .env
just db-up          # PostgreSQL 18 + Redis 8 в Docker
just migrate        # sqlx migrate run
just billing        # терминал 1: имитация платёжного провайдера, :8090
just api            # терминал 2: HTTP API, :8080
just worker         # терминал 3: outbox relay + периодические задачи, :8081
curl -s localhost:8080/health/ready
```

Полный стек в контейнерах: `docker compose --profile full up --build`, smoke-сценарий —
`./scripts/smoke.sh`. OpenAPI-документ — `GET /api/docs/openapi.json`.

Проверка качества (то же, что делает CI): `just check` = `cargo fmt --check` +
`cargo clippy -D warnings` + `cargo sqlx prepare --check` + `cargo nextest run`.

## Структура workspace

```text
crates/
  courseflow-core/    домен: типы, инварианты, переходы состояний, политики доступа, порты
  courseflow-app/     use cases + адаптеры: SQLx-репозитории, Redis, billing-клиент, auth, outbox
  courseflow-api/     Axum: роутер, экстракторы, DTO, RFC 9457, OpenAPI, WebSocket/SSE, метрики
  courseflow-worker/  outbox relay, доставка уведомлений, очистка по расписанию
  billing-mock/       платёжный провайдер-заглушка с подписанными webhook'ами и сценариями сбоев
migrations/           SQL-миграции (sqlx migrate)
.sqlx/                offline-метаданные для query!() — коммитятся
scripts/smoke.sh      end-to-end сценарий поверх Docker Compose
docs/                 архитектурные решения и карта API
```

Правило зависимостей: `core` не знает ни о HTTP, ни о SQL; `app` знает о PostgreSQL/Redis, но
не о HTTP; `api` и `worker` — тонкие оболочки над `app`.

## Артефакты по главам

| Глава | Что появляется в проекте |
| --- | --- |
| 2 | `crates/courseflow-core/src/*` — `ids.rs`, `money.rs`, `users.rs`, `courses.rs`, `lessons.rs`, `enrollments.rs`, `progress.rs`, `billing.rs`, `notifications.rs`, `policy.rs`, `errors.rs`, `ports.rs` |
| 3 | `Cargo.toml` (workspace, lints, профили), `rustfmt.toml`, `deny.toml`, `justfile`, `.env.example`, `docker-compose.yml` (postgres/redis), `crates/courseflow-app/src/config.rs`, `telemetry.rs` |
| 4 | `courseflow-app/src/resilience/{retry.rs, breaker.rs}`, `courseflow-api/src/http/shutdown.rs`, `courseflow-worker/src/relay.rs` (цикл с `select!` и `CancellationToken`) |
| 5 | `courseflow-api/src/app.rs`, `state.rs`, `http/middleware.rs`, `http/health.rs`, `http/extractors/*`, `main.rs` (`axum::serve` + graceful shutdown) |
| 6 | `courseflow-api/src/http/error.rs` (RFC 9457), `features/*/dto.rs`, `courseflow-app/src/shared/pagination.rs`, `http/openapi.rs`, `tests/contract.rs` + snapshot |
| 7 | `http/extractors/validated.rs`, `courseflow-core` newtype'ы (`Email`, `CourseTitle`, `Slug`, `Money`), `courseflow-app/src/errors.rs`, маппинг в `http/error.rs` |
| 8 | разбиение на crate'ы; `features/*/routes.rs` + `courseflow-app/src/<feature>/{service.rs, repo.rs}`; composition root `app::build_state` |
| 9 | `migrations/0001…0006`, `courseflow-app/src/db/mod.rs`, все `repo.rs` (`query!`, `query_as!`, `QueryBuilder`, `FOR UPDATE`, `SKIP LOCKED`), `.sqlx/`, `sqlx.toml` |
| 10 | `courseflow-app/src/auth/*` (Argon2id, JWT, refresh-ротация, action tokens), `http/extractors/auth.rs`, `features/auth`, `features/users` |
| 11 | `courseflow-app/src/cache/*` (кэш курсов, rate limiter на Lua, idempotency guard), `tests/redis.rs` |
| 12 | `courseflow-app/src/billing/{client.rs, webhook.rs, service.rs}`, `http/extractors/signed_webhook.rs`, `crates/billing-mock`, `tests/billing_client.rs` |
| 13 | `courseflow-app/src/outbox/*`, `crates/courseflow-worker/*`, `migrations/0006_outbox_notifications.sql` |
| 14 | `features/notifications/routes.rs` (WebSocket, SSE), `courseflow-app/src/notifications/bus.rs` (Redis pub/sub) |
| 15 | `courseflow-api/tests/*` (`#[sqlx::test]`, `oneshot`), `courseflow-app/tests/*` (wiremock, Redis), `courseflow-worker/tests/relay.rs`, `Config::for_tests` |
| 16 | `http/middleware.rs` (spans, request id, RED-метрики), `http/metrics.rs`, shutdown в `main.rs` и worker'е, `[profile.release]` |
| 17 | `Dockerfile` (multi-stage, cargo-chef), `docker-compose.yml` (profile `full`), `.github/workflows/ci.yml`, `scripts/smoke.sh`, `courseflow-api migrate` |

## Переменные окружения

Все с префиксом `COURSEFLOW_`; обязательные — `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET` (≥ 32 байт),
`BILLING_WEBHOOK_SECRET`. Остальные имеют значения по умолчанию, см. `crates/courseflow-app/src/config.rs`.
`DATABASE_URL` без префикса нужен только `sqlx-cli` и макросам `query!` во время компиляции
(или `SQLX_OFFLINE=true` с данными из `.sqlx/`).

## Сценарии billing-mock

Сценарий задаётся заголовком `X-Mock-Scenario` или копейками суммы курса: `.13` — платёж
отклонён, `.55` — медленный ответ (таймаут у клиента), `.99` — провайдер отвечает 503,
`.22` — webhook приходит дважды, `.77` — успех и затем возврат. Всё остальное — успех.

## Эксплуатационные заметки

* Миграции применяются отдельным шагом: `courseflow-api migrate` (тот же образ, сервис
  `migrate` в Compose) — приложение при старте схему не меняет.
* Redis необязателен для чтения: без него API стартует, кэш и rate limit выключены
  (fail-open), а `Idempotency-Key` для покупок отвечает 503 (fail-closed).
* `/health/live` — процесс жив; `/health/ready` — PostgreSQL доступен (Redis только
  отражается в `checks`). `/metrics` — Prometheus.
* Остановка: SIGTERM → перестаём принимать соединения → ждём in-flight до
  `COURSEFLOW_SHUTDOWN_TIMEOUT_SECS` (20 с) → выход. В Compose `stop_grace_period: 25s`.
