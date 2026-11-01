# Production checklist Atrium (урок 17.4)

| Область | Пункт | Статус | Где |
| --- | --- | --- | --- |
| Сборка | версия из тега, build-info, `/info` | выполнено | `Dockerfile.*`, `deploy.yml`, `HealthRoutes.kt` |
| Сборка | lockfile, каталог без диапазонов | частично | `gradle/libs.versions.toml`; `--write-locks` — задание |
| Сборка | apiCheck клиента | выполнено | `atrium-client/api` |
| Тесты | required checks, kover 70 %, smoke | выполнено | `ci.yml`, `scripts/smoke.sh` |
| БД | миграции чистая база, append-only | выполнено | `MigrationsTest`, шаг CI |
| БД | планы, statement_timeout, пул | выполнено | `QueryPlansTest`, `StatementTimeoutTest`, `connection-init-sql` |
| Наблюдаемость | поля логов, PII, метрики, алерты | выполнено | `logback.xml`, `LogPiiTest`, `MetricsNamesTest`, `docs/metrics.md` |
| Контейнер | non-root, память, CDS, пробы, остановка | выполнено | `docker/`, `Lifecycle.kt`, `ApplicationScopeLifecycle.kt` |
| Безопасность | секреты, JWT, лимиты, trivy | частично | `Env.secret`, `Security.kt`, `RateLimiting.kt`; Dependabot — вне репозитория |
| Контракты | OpenAPI, Problem Details, идемпотентность | выполнено | `OpenApiContractTest`, `ContractCase.kt`, `JdbcIdempotencyStore` |
| Интеграции | таймауты, retry, breaker, DLQ | частично | `ResilientPaymentGateway`; DLQ — задание 17.3 |
| Эксплуатация | runbook, откат, нагрузка | частично | `docs/runbook.md`, `docs/perf.md` — задание |

Не сделано и почему: multi-tenant (нет требования), реальная аутентификация участников (внешний IdP — вне курса), миграция данных из старой системы (нет старой системы).
