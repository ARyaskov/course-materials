# .NET-слой Waybill: заметки по главе 12

## Проекты

| Проект | Назначение | Application Name |
| --- | --- | --- |
| `src/Waybill.Data` | SqlConnectionFactory (+retry, SESSION_CONTEXT), Resilience, JSON TypeHandler, модели, репозитории | — (библиотека) |
| `src/Waybill.Api` | minimal API: webhooks, events (TVP), timeline + ETag, PATCH If-Match, versions, list, health; SqlExceptionMiddleware; OpenTelemetry | `Waybill.Api` |
| `src/Waybill.Simulator` | нагрузка: `--mode webhooks | api-tvp | tvp | hot`, `--workers`, `--seconds`, `--batch`, `--api`, `--connection`, `--keep` | `Waybill.Simulator` |
| `src/Waybill.Migrator` | миграции `sql/**` (глава 1) | `Waybill.Migrator` |
| `tests/Waybill.Tests` | xunit, интеграционные против локальной базы (SKIP без базы) | `Waybill.Tests` |

Сборка: `dotnet build Waybill.slnx`. SDK на стенде: 11.0 RC (targeting net10.0 с `RollForward=LatestMajor`). `InvariantGlobalization` выключен — SqlClient его не поддерживает.

## Правила доступа к данным

1. `Microsoft.Data.SqlClient` 6.1.1; `System.Data.SqlClient` не используется.
2. Соединение — на единицу работы (`await using var conn = await db.OpenAsync(user, ct)`); никаких статических соединений; MARS выключен.
3. Все параметры — с явным `SqlDbType`/`DbType` и длиной; `AddWithValue` запрещён; `varchar` через `DbString { IsAnsi = true, Length = n }`; JSON — `SqlDbType.Json`.
4. `CancellationToken` — во все вызовы (`CommandDefinition`); `CommandTimeout` — 30 с по умолчанию, `/health` — 5 с, обслуживание — 0.
5. Ошибки: по `SqlException.Number` (`SqlErrors`), никогда по тексту. Deadlock 1205 → `Resilience.RetryOnDeadlockAsync` вокруг метода репозитория; transient → retry-провайдер соединения; таймаут и 50xxx — не повторять.
6. Транзакции — в процедурах; клиентские — редко, с `SET XACT_ABORT ON`, одно соединение, `Rollback` в `catch` с проглатыванием «зомби».
7. Пользователь — заголовок `X-User` → `SESSION_CONTEXT('user')` (до аутентификации главы 15); trace id → `SESSION_CONTEXT('trace')` + `CONTEXT_INFO`.
8. Агрегаты для API строит сервер (`JSON_OBJECT`/`FOR JSON`); клиент не пересобирает JSON.
9. EF Core допустим только для `ref`/`crm`/`bill` в админке; DDL — только SQL-скрипты.

## HTTP ↔ SQL (SqlExceptionMiddleware)

| SQL | HTTP |
| --- | --- |
| 50001 not found, 50031 carrier, 50050 merchant | 404 |
| 50030 not JSON | 400 |
| 50032, 50033, 50051, 547 | 422 |
| 50070 version conflict | 412 |
| 2627 / 2601 | 409 |
| 50061 applock, 1205 (после повторов) | 503 |
| -2 timeout | 504 |
| прочие 50xxx | 400 |
| прочие | 500 |

## Замеры симулятора (заполнить на стенде)

| Режим | Workers | Batch | events/s | p50 ms | p95 ms | ошибки |
| --- | --- | --- | --- | --- | --- | --- |
| tvp | 4 | 20 | | | | |
| api-tvp | 8 | 20 | | | | |
| webhooks | 8 | 20 | | | | |
| hot | 8 | 20 | | | | 1205-повторы: |

## Известные компромиссы

* Таймлайн — два обращения к базе (документ + `RowVer`); кандидат на объединение через `OUTPUT`-параметр.
* Тесты без базы «проходят» с выводом `SKIP:` — до Testcontainers (глава 16).
* `OpenTelemetry.Instrumentation.SqlClient` — beta-пакет; `OpenTelemetry.Api` 1.14 с известной уязвимостью умеренной серьёзности (обновить при выходе патча).
