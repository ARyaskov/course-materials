# CourseFlow API

Финальный проект курса **«C# Backend Developer: ASP.NET Core, .NET 11, базы данных»** (Stepik, курс 174388).
Это тот самый код, который по частям разбирается в уроках, — в первую очередь в Главе 23, — собранный
в запускаемое приложение. Всё, о чём говорится в уроках, здесь есть и работает: Minimal APIs, EF Core
с миграциями на PostgreSQL, Redis, RabbitMQ + MassTransit + Outbox, GraphQL, SignalR, JWT с ротацией
refresh-токенов, Serilog + OpenTelemetry, Testcontainers, Docker Compose, Aspire, GitHub Actions.

## Стек

| Область | Технологии |
|---|---|
| Платформа | .NET 11 (RC), C# 15 (preview), ASP.NET Core 11 |
| API | Minimal APIs (REST, `/api/v1/*`), Hot Chocolate (GraphQL, `/graphql`), SignalR (`/hubs/notifications`) |
| Данные | PostgreSQL 17 + EF Core 11 (migrations, snake_case, `xmin`-concurrency, GIN/pg_trgm), Dapper для отчётов |
| Кэш | Redis 8: `IDistributedCache` (cache-aside) + `SET NX` для idempotency keys |
| Messaging | RabbitMQ 4 + MassTransit 8 (Apache-2.0) + EF Core Outbox/Inbox |
| Auth | JWT (HS256, `JsonWebTokenHandler`), refresh-токены с хешем и reuse detection, bcrypt, policy-based authorization |
| Ошибки | RFC 9457 Problem Details, `Result<T>` + `Error`, `GlobalExceptionHandler`, FluentValidation (422) |
| Observability | Serilog (compact JSON), OpenTelemetry (traces/metrics/logs → OTLP), Prometheus `/metrics`, `/health/live` + `/health/ready` |
| Тесты | xUnit v3 (Microsoft.Testing.Platform), FluentAssertions 7, NSubstitute, Testcontainers, MassTransit test harness |
| Инфраструктура | Docker Compose, Dockerfile (multi-stage, non-root), .NET Aspire AppHost, GitHub Actions |

## Структура

```text
c-sharp-backend/
├── CourseFlow.slnx
├── global.json                      # пин .NET 11 SDK + runner Microsoft.Testing.Platform
├── Directory.Build.props            # общие свойства проектов
├── docker-compose.yml               # postgres, redis, rabbitmq, jaeger, prometheus (+ api по профилю)
├── Dockerfile, prometheus.yml, .env.example
├── .github/workflows/              # учебные примеры CI/CD проекта
├── src/
│   ├── CourseFlow.Api/              # основной API
│   │   ├── Program.cs               # композиция и middleware pipeline
│   │   ├── ModuleRegistration.cs    # AddModules / MapModules
│   │   ├── Common/                  # Auth, Errors (Result/Error), Middleware, Validation
│   │   ├── Infrastructure/          # Data (AppDbContext, Migrations, Seeder), Caching, Messaging
│   │   ├── GraphQL/                 # Query, Mutation
│   │   └── Modules/                 # Users, Courses, Lessons, Enrollment, Progress, Billing, Notifications
│   │       └── <Module>/            # Domain/, Services/, Endpoints/, Infrastructure/, Consumers/, Contracts.cs
│   ├── CourseFlow.Contracts/        # контракты сообщений (PaymentCompleted, EnrollmentCreated, ...)
│   ├── CourseFlow.ServiceDefaults/  # OpenTelemetry, health checks, service discovery, resilience
│   └── CourseFlow.AppHost/          # Aspire-оркестрация
└── tests/
    ├── CourseFlow.Tests.Unit/
    └── CourseFlow.Tests.Integration/
```

Команды ниже выполняются из папки проекта, содержащей `CourseFlow.slnx`.
Учебные примеры CI/CD лежат в `.github/workflows/ci.yml` и `cd.yml` внутри
этой папки. Они рассчитаны на перенос проекта в отдельный репозиторий,
где папка проекта станет корнем. В общем репозитории учебных материалов
эти workflow не запускаются.

## Требования

- **.NET 11 SDK** (RC1 или новее — см. `global.json`)
- **Docker** (Docker Desktop / Docker Engine) — для инфраструктуры и интеграционных тестов

## Запуск

### Вариант 1: Docker Compose + `dotnet run`

```bash
cp .env.example .env            # при необходимости поменяйте порты
docker compose up -d            # postgres, redis, rabbitmq, jaeger, prometheus
dotnet run --project src/CourseFlow.Api
```

API поднимется на `http://localhost:8080`, применит миграции и наполнит базу демо-данными
(`Seed:Enabled` в `appsettings.Development.json`).

- Scalar (OpenAPI UI): <http://localhost:8080/scalar/v1>
- GraphQL IDE: <http://localhost:8080/graphql>
- RabbitMQ Management: <http://localhost:15672> (courseflow / courseflow)
- Jaeger: <http://localhost:16686> — трейсы приходят, если задан `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317`
- Prometheus: <http://localhost:9090>

Полностью в контейнерах (API собирается из `Dockerfile`):

```bash
docker compose --profile api up -d --build
```

### Вариант 2: Aspire (рекомендуется)

```bash
dotnet run --project src/CourseFlow.AppHost
```

AppHost поднимет PostgreSQL, Redis и RabbitMQ в контейнерах, запустит API и откроет Dashboard
с логами, трейсами и метриками. Ссылка с токеном входа печатается в консоль.

### Демо-пользователи

| Роль | Email | Пароль |
|---|---|---|
| Admin | `admin@courseflow.io` | `Passw0rd!` |
| Instructor | `instructor@courseflow.io` | `Passw0rd!` |

Плюс опубликованный демо-курс с тремя уроками (первый — бесплатный).

## End-to-end сценарий (Глава 23.11)

```text
1.  POST /api/v1/auth/register                         → accessToken + refreshToken
2.  POST /api/v1/auth/login                            (instructor@courseflow.io)
3.  POST /api/v1/courses                               (Instructor) → courseId
4.  POST /api/v1/courses/{id}/lessons                  (Instructor)
5.  POST /api/v1/courses/{id}/publish                  (Instructor) → CoursePublished в Outbox
6.  POST /api/v1/billing/payments  { courseId }        (Student, заголовок Idempotency-Key)
        → PaymentCompleted → Enrollment → EnrollmentCreated → Progress + Notification (БД + SignalR)
7.  GET  /api/v1/enrollments
8.  GET  /api/v1/progress/{courseId}
9.  POST /api/v1/progress/lessons/{lessonId}/complete  → после последнего урока CourseCompleted
10. GET  /api/v1/notifications
```

Вся цепочка после шага 6 асинхронная: сообщения проходят через таблицу `outbox_message`
и RabbitMQ, поэтому записи появляются через доли секунды, а не в ответе на запрос.

## Endpoints

| Метод и путь | Доступ | Описание |
|---|---|---|
| `POST /api/v1/auth/register` · `login` · `refresh` | anon | регистрация, вход (rate limit 5/мин по IP), ротация refresh-токена |
| `GET /api/v1/users/me` · `GET /users/{id}` · `POST/DELETE /users/{id}/follow` | auth | профиль, подписка на автора |
| `GET /api/v1/courses` · `GET /courses/{id}` | anon | каталог (`?search=&page=&pageSize=`), карточка (кэш Redis 5 мин) |
| `GET /courses/mine` · `POST /courses` · `PUT /courses/{id}` · `POST /courses/{id}/publish` · `GET /courses/{id}/stats` | Instructor | управление курсом; `stats` — отчёт через Dapper |
| `GET /api/v1/courses/{id}/lessons` · `GET .../lessons/{lessonId}` | anon | платные уроки без записи отдаются как превью |
| `POST/PUT/DELETE .../lessons` · `PUT .../lessons/reorder` | Instructor | управление уроками |
| `POST /api/v1/billing/payments` · `GET /payments` · `GET /payments/{id}` | auth | mock-оплата (`cardToken: "fail_card"` — отказ), idempotency через `Idempotency-Key` |
| `GET /api/v1/enrollments` · `GET /enrollments/check/{courseId}` | auth | мои записи |
| `GET /api/v1/progress/{courseId}` · `POST .../lessons/{id}/complete` · `PUT .../lessons/{id}/video` | auth | прогресс |
| `GET /api/v1/notifications` · `GET /unread-count` · `PUT /{id}/read` · `PUT /read-all` | auth | уведомления |
| `WS /hubs/notifications` | auth | real-time уведомления (токен — `?access_token=` или заголовок) |
| `POST /graphql` | — | `publishedCourses`, `course`, `courseLessons`, `me`, `myEnrollments`, `myProgress`; мутации `createCourse`, `publishCourse`, `markLessonCompleted` |
| `GET /health/live` · `GET /health/ready` · `GET /metrics` | — | liveness / readiness (Postgres, Redis, шина) / Prometheus |

## Артефакты по главам

| Глава | Что искать в проекте |
|---|---|
| 4. SDK, проекты, NuGet, конфигурация | `global.json`, `Directory.Build.props`, `.config/dotnet-tools.json`, `src/CourseFlow.Api/appsettings*.json`, `Common/Auth/JwtOptions.cs` (типизированные опции + `ValidateOnStart`) |
| 5. ASP.NET Core и Minimal APIs | `Program.cs` (middleware pipeline), `Modules/*/Endpoints/*Module.cs` (route groups), `Common/Validation/ValidationFilter.cs` (endpoint filter), `Common/Middleware/` |
| 6–7. REST, validation, typed errors | `Common/Errors/` (`Result`, `Error`, `ToHttpResult`), `Common/Middleware/GlobalExceptionHandler.cs`, `Modules/*/Contracts.cs` (DTO + FluentValidation) |
| 8. Vertical Slice + Modular Monolith | `Modules/<Module>/{Domain,Services,Endpoints,Infrastructure,Consumers}`, `ModuleRegistration.cs` |
| 9. PostgreSQL и EF Core | `Infrastructure/Data/AppDbContext.cs`, `Infrastructure/Data/Migrations/`, `Modules/*/Infrastructure/*DbConfiguration.cs` (индексы, `xmin`, частичные индексы), `CourseService.GetStatsAsync` (Dapper), `NotificationService.MarkAllAsReadAsync` (`ExecuteUpdate`) |
| 11. GraphQL | `GraphQL/Query.cs`, `GraphQL/Mutation.cs`, регистрация Hot Chocolate в `Program.cs` |
| 12. Real-time | `Modules/Notifications/Services/NotificationDispatcher.cs` (hub, `IUserIdProvider`), `Common/Auth/AuthExtensions.cs` (токен из query string для `/hubs`) |
| 13. Безопасность | `Common/Auth/` (JWT, bcrypt, `ICurrentUser`, политики), `Modules/Users/Services/AuthService.cs` (ротация refresh-токенов, reuse detection), rate limiting и security headers в `Program.cs` |
| 14. Redis | `CourseService` (cache-aside через `IDistributedCache`), `Infrastructure/Caching/IdempotencyStore.cs` (`SET NX`) |
| 16–17. Background и messaging | `Modules/Users/Infrastructure/RefreshTokenCleanupWorker.cs` (`BackgroundService` + `PeriodicTimer`), `Infrastructure/Messaging/MessagingExtensions.cs` (MassTransit, RabbitMQ, Outbox/Inbox), `Modules/*/Consumers/`, `src/CourseFlow.Contracts/Events.cs` |
| 18. Observability | `src/CourseFlow.ServiceDefaults/Extensions.cs` (OpenTelemetry, health checks), Serilog в `Program.cs` и `appsettings.json`, `Common/Middleware/CorrelationIdMiddleware.cs`, метрика `courseflow.payments` в `BillingService`, `prometheus.yml` |
| 19. Testing | `tests/CourseFlow.Tests.Unit/`, `tests/CourseFlow.Tests.Integration/` (Testcontainers, `WebApplicationFactory`, MassTransit test harness, SignalR-клиент) |
| 20. Docker | `Dockerfile`, `docker-compose.yml`, `.env.example`, `.dockerignore` |
| 21. Aspire | `src/CourseFlow.AppHost/`, `src/CourseFlow.ServiceDefaults/`, Aspire-интеграции в `Program.cs` |
| 22. CI/CD | [CI](.github/workflows/ci.yml), [CD](.github/workflows/cd.yml), `Makefile` |
| 23. Финальный проект | всё вместе: `Program.cs`, семь модулей, тесты, инфраструктура |

## Конфигурация

Ключи читаются из `appsettings*.json`, переменных окружения (`Jwt__SecretKey`) и User Secrets.
Обязательные в любом окружении:

```jsonc
{
  "ConnectionStrings": {
    "courseflow": "Host=localhost;Port=5432;Database=courseflow;Username=courseflow;Password=courseflow",
    "redis": "127.0.0.1:6379",
    "rabbitmq": "amqp://courseflow:courseflow@localhost:5672/"
  },
  "Jwt": { "SecretKey": "минимум 32 символа", "AccessTokenMinutes": 15, "RefreshTokenDays": 30 },
  "Cors": { "AllowedOrigins": ["http://localhost:3000"] },
  "Seed": { "Enabled": false }
}
```

Секрет JWT валидируется при старте (`ValidateOnStart`): с пустым ключом приложение не поднимется.
Миграции применяются автоматически во всех окружениях, кроме `Production`; сид — только при `Seed:Enabled=true`.

## Миграции

```bash
dotnet tool restore
dotnet ef migrations add <Name> --project src/CourseFlow.Api --startup-project src/CourseFlow.Api --output-dir Infrastructure/Data/Migrations
```

## Тесты

```bash
dotnet test tests/CourseFlow.Tests.Unit          # ~40 тестов, без инфраструктуры
dotnet test tests/CourseFlow.Tests.Integration   # PostgreSQL + Redis в Testcontainers, нужен Docker
```

Интеграционные тесты поднимают API через `WebApplicationFactory`, RabbitMQ заменён MassTransit test harness
(in-memory транспорт), но Outbox, consumer-ы, Redis-кэш и SignalR работают по-настоящему.

## Что стоит знать

- **Версии.** .NET 11 и C# 15 на момент написания — RC/preview; используется EF Core 11 preview.6, потому что
  пакет Npgsql для RC1 ссылается на сборку EF из внутреннего feed Microsoft. После GA достаточно поднять версии
  в `src/CourseFlow.Api/CourseFlow.Api.csproj` и `.config/dotnet-tools.json`.
- **Лицензии.** MassTransit 9 и FluentAssertions 8 перешли на коммерческие лицензии; проект остаётся на
  MassTransit 8.5 и FluentAssertions 7.2 (Apache-2.0).
- **Redis и IPv6.** В строке подключения к Redis используется `127.0.0.1`, а не `localhost`: StackExchange.Redis
  пробует `::1`, а Docker на Windows публикует порт только на IPv4.
