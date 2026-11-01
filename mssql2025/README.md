# Waybill — трекинг отправлений на SQL Server 2025

Сквозной проект курса «Эффективная работа с современным Microsoft SQL Server 2025/MSSQL».

Waybill — backend системы трекинга отправлений для логистического оператора (3PL): магазины-арендаторы создают отправления, перевозчики присылают webhook-события в разных JSON-форматах, система дедуплицирует и нормализует события, ведёт историю статусов, считает SLA по перевозчикам, рассылает уведомления через outbox и ищет похожие инциденты векторным поиском.

Учебные данные локализованы для РФ: русские описания, города и регионы России,
шестизначные почтовые индексы, код страны `RU`, валюта `RUB`. Имена, телефоны,
магазины и перевозчики в примерах вымышлены; это синтетика, а не выгрузка клиентов.
Служебные коды перевозчиков (`FASTEX`, `NORDPOST`, `CITYRUN`), статусов и JSON-поля
сохраняют формат внешних API. В webhook-примерах NORDPOST время передаётся по
московскому времени (`+03:00`), а в базе хранится в UTC.

## Быстрый старт

Требования: SQL Server 2025 (17.x) — локальный экземпляр или Docker; PowerShell 7; .NET 10 SDK (для `src/`).

```powershell
# 1. Экземпляр: локальный (Windows-аутентификация) или контейнер
docker compose up -d            # необязательно, если есть локальный экземпляр

# 2. Схема и данные: все sql/**/*.sql по порядку, журнал в dbo.SchemaMigrations
./scripts/apply.ps1                                   # локальный экземпляр
./scripts/apply.ps1 -Server "localhost,1433" -User sa -Password 'Waybill_Dev_2025!'   # контейнер

# 3. Проверка
./scripts/query.ps1 -File ./sql/01-start/010_catalog_report.sql

# 4. .NET: API, тесты, нагрузка (глава 12)
dotnet build Waybill.slnx
dotnet run --project src/Waybill.Api                 # http://localhost:5080/health, запросы — src/Waybill.Api/waybill.http
dotnet test tests/Waybill.Tests
$env:WAYBILL_TEST_MODE = 'container'; dotnet test tests/Waybill.Tests   # Testcontainers: свой SQL Server 2025 + миграции (глава 16)
./scripts/reset-stand.ps1 -Force                                       # стенд с нуля: drop → apply → tests → tSQLt → снимок дрейфа
dotnet run --project src/Waybill.Simulator -- --mode webhooks --workers 8 --seconds 20
```

Строка подключения для .NET: `Waybill:ConnectionString` в `src/Waybill.Api/appsettings.json` (переопределяется переменной `Waybill__ConnectionString`); симулятор и тесты читают `WAYBILL_CONNECTION`.

Строки подключения — в `.env.example`. Скрипты идемпотентны: `./scripts/apply.ps1 -Force` переприменяет всё без последствий.

Учебный пример CI — `.github/workflows/ci.yml` внутри этой папки. Он рассчитан на отдельный репозиторий с проектом в корне; в общем репозитории материалов workflow не запускается.

## Структура

```text
docker-compose.yml       SQL Server 2025 в контейнере (Developer, Agent включён, UTF-8-коллация)
scripts/apply.ps1        применяет sql/** (разбиение по GO, журнал dbo.SchemaMigrations, -Only, -Force)
scripts/query.ps1        выполняет запрос или файл и печатает результат
sql/<NN-глава>/          T-SQL по главам курса; применяются лексикографически
src/                     .NET 10: Waybill.Migrator, Waybill.Data, Waybill.Api, Waybill.Simulator
tests/                   xUnit-интеграционные тесты против SQL Server 2025
data/                    CSV/JSON для BULK INSERT (монтируется в контейнер как /import)
docs/                    заметки о стенде
```

## База Waybill

- Compat level 170, коллация `Latin1_General_100_CI_AS_SC_UTF8`, RCSI, ADR, optimized locking, Query Store.
- Файловые группы: `PRIMARY`, `FG_Events` (поток событий трекинга), `FG_Memory` (In-Memory OLTP, глава 13 — добавляется необратимо).
- Схемы: `ref` (справочники), `crm` (арендаторы), `ship` (адреса, отправления, события), `ops` (инциденты, outbox, процедуры), `bill` (тарифы), `analytics` (витрины), `dbo.SchemaMigrations` (журнал).

## Артефакты по главам

| Глава | Что добавлено | Файлы |
| --- | --- | --- |
| 1 | База Waybill, схемы, журнал миграций, диагностические запросы | `sql/01-start/001_database.sql`, `002_schemas.sql`, `010_catalog_report.sql`, `020_whats_running.sql`, `scripts/apply.ps1`, `scripts/query.ps1`, `docker-compose.yml`, `docs/environment.md` |
| 2 | Полигон `demo.*` (2 000 отправлений), примеры T-SQL 2025, шаблон процедуры с TRY/CATCH и журналом ошибок, поиск с динамическим SQL, TVP-ingest на полигоне | `sql/02-tsql/000_batch_demo.sql` … `110_pg_to_tsql.sql` |
| 3 | DDL ядра: `ref`/`crm`/`ship`/`ops`, ограничения (CHECK с `REGEXP_LIKE`), seed, вычисляемые столбцы, `PublicId`, диагностика схемы; `Waybill.Migrator` | `sql/03-schema/010_ref.sql` … `070_shipment_publicid.sql`, `src/Waybill.Migrator/*`, `Directory.Build.props`, `Waybill.slnx`, `docs/model-notes.md` |
| 4 | Индексы под запросы API (покрывающие, фильтрованные, по вычисляемым столбцам), `NCCI_TrackingEvent`, витрина `analytics.CarrierSla`, ревизия через DMV, `ops.usp_MaintainIndexes` | `sql/04-indexes/010_indexes_core.sql` … `050_index_maintenance.sql`, `docs/index-notes.md` |
| 5 | json-столбцы (`RawPayload`, `Attributes`, `Settings`, `Outbox.Payload`), `ref.CarrierStatusMap`, `ops.tvf_ParseWebhook`, `ship.usp_PatchShipmentAttributes`, `ops.usp_ValidateWebhook`, индексы по извлечённым полям, JSON-индекс (preview) | `sql/05-json/010_json_columns.sql` … `080_seed_payloads.sql`, `data/webhooks/*.json`, `docs/json-notes.md` |
| 6 | Regex-нормализация (`fn_NormalizeTrackingNumber`, `crm.fn_NormalizePhone`, `ship.fn_NormalizeStreet`), миграция `NormalizedKey`/`TrackingNumberNormalized`, нечёткая дедупликация адресов (`usp_FindSimilarAddress`, `usp_ReportAddressDuplicates`), 20 инцидентов, full-text (`ops.usp_SearchIncidents`), строковые рецепты | `sql/06-strings/010_regex_demo.sql` … `050_string_recipes.sql` |
| 7 | `ops.tt_TrackingEventIn`, `ops.WebhookInbox`, `ops.RejectedEvent`, функции таймлайна/сводки, `ops.usp_IngestTrackingEvents`, `ops.usp_ReceiveWebhook`, `ship.usp_CreateShipment`, `ship.usp_GetShipmentTimeline`, аудит-триггеры, `sp_invoke_external_rest_endpoint` (`ops.usp_LookupPostalCode`), smoke и deploy-проверки | `sql/07-procs/010_types.sql` … `080_deploy_checks.sql`, `docs/errors.md`, `docs/procs-notes.md` |
| 8 | Очередь outbox (`ops.usp_DequeueOutbox` с READPAST/UPDLOCK/ROWLOCK, аренда, `usp_CompleteOutbox`/`usp_FailOutbox`, `vw_OutboxPoison`), прикладные блокировки (`ops.usp_RunExclusive`, `ship.usp_CreateShipmentSerialized`), `ship.Shipment.RowVer` + `usp_UpdateShipmentIfMatch`/`usp_GetShipmentVersion` (ETag), диагностика транзакций, блокировок, deadlock-ов, PVS, нагрузка на горячие строки | `sql/08-concurrency/000_transactions_demo.sql` … `070_hot_rows_demo.sql`, `scripts/hot-rows.ps1`, `docs/concurrency-notes.md` |
| 9 | Объём данных (50k отправлений), Query Store: настройки, автокоррекция, IQP-конфигурация, `ops.vw_QueryStore*`; XEvents-сессии `waybill_*` и `ops.vw_Xe*`; снимки wait stats; SLA-витрина (`analytics.usp_RefreshCarrierSla`, `usp_CarrierSlaReport`); демо sniffing / batch mode / хинтов | `sql/09-performance/005_seed_volume.sql` … `050_hints_demo.sql`, `docs/performance-notes.md` |
| 10 | Секционирование `ship.TrackingEvent` по месяцу (`pf_MonthlyEvents`/`ps_MonthlyEvents`), файловая загрузка через staging (`ops.usp_ImportEventFile`, `ops.usp_ImportWebhookFile`, `ops.Setting`), sliding window (`ops.usp_MaintainEventPartitions`, `ship.TrackingEventStage`, архив ordered CCI, `ship.vw_TrackingEventAll`), батчевая чистка (`ops.usp_PurgeInbox`, `ship.usp_RecomputeLastEventAt`), генератор 1M событий, `analytics.tvf_SlaRollup` | `sql/10-bulk/010_partitioning.sql` … `060_aggregates_demo.sql`, `data/events/nordpost-2026-08.csv`, `docs/bulk-notes.md` |
| 11 | Temporal `ship.Shipment` (+`ModifiedBy`, функции истории), Change Tracking (`ops.usp_GetShipmentChanges`), CDC (`ops.usp_GetShipmentCdcChanges`, при Agent), ledger `bill.Tariff`/`bill.Surcharge` + digest, CES `waybill-shipments` (при Event Hubs), outbox как контракт (`ops.usp_EmitOutbox`, `ops.OutboxDelivery`, `ops.vw_OutboxStats`) | `sql/11-history/010_temporal.sql` … `050_outbox_notifications.sql`, `docs/history-notes.md` |
| 12 | `Waybill.Data` (SqlConnectionFactory + retry, SessionContext, JSON TypeHandler, репозитории Shipment/Ingest/Outbox с TVP и SqlBulkCopy), `Waybill.Api` (webhooks, events, timeline + ETag, PATCH If-Match, versions, list, health; SqlExceptionMiddleware; OpenTelemetry), `Waybill.Simulator`, `Waybill.Tests` | `src/Waybill.Data`, `src/Waybill.Api`, `src/Waybill.Simulator`, `tests/Waybill.Tests`, `docs/dotnet-notes.md` |
| 13 | Партиционированная очередь outbox + `OutboxDispatcher` в Waybill.Api, Service Broker для внутренних потребителей (`usp_SendOutboxMessage`, активации), In-Memory OLTP (`FG_Memory` — необратимо; `ops.EventSeen`, `ops.RateCounter`, native-процедуры), задания Agent (6), Resource Governor + tempdb governance | `sql/13-async/010_outbox_queue.sql` … `050_resource_governor.sql`, `src/Waybill.Api/OutboxDispatcher.cs`, `docs/async-notes.md` |
| 14 | `vector(768)` у инцидентов и чанков (`ops.IncidentChunk`), toy-эмбеддинг для стенда (`ops.fn_ToyEmbedding`), `EXTERNAL MODEL WaybillEmbeddings` + `AI_GENERATE_EMBEDDINGS` (при `ai.enabled`), чанкинг (`usp_ChunkIncident`), точный kNN (`usp_FindSimilarIncidents`), гибридный поиск RRF (`usp_SearchIncidentsHybrid`), DiskANN + `VECTOR_SEARCH` (при `ai.vector_index`; таблица становится read-only), `EmbeddingService`, эндпоинты `/incidents/*` | `sql/14-ai/010_vector_columns.sql` … `040_vector_index.sql`, `src/Waybill.Api/EmbeddingService.cs`, `src/Waybill.Data/Repositories/IncidentRepository.cs`, `docs/ai-notes.md` |
| 15 | Схема `sec`, роли `waybill_api`/`waybill_ingest`/`waybill_readonly`/`waybill_ops` и логины стенда, RLS `sec.MerchantIsolation` по `SESSION_CONTEXT('MerchantId')`, DDM для PII, Always Encrypted (`ship.RecipientContact`, CMK по настройке), TDE (`security.tde`), SQL Audit `Waybill_Audit` + `sec.tvf_AuditEvents`, безопасный динамический SQL (`ship.usp_ListShipmentsSorted`), `X-Merchant-Id` → `SessionContext.SetMerchantAsync` в API | `sql/15-security/010_principals.sql` … `050_injection.sql`, `src/Waybill.Data/WaybillDb.cs`, `docs/security-notes.md` |
| 16 | FULL recovery + ADR, `ops.vw_LogStatus`/`vw_PvsStats`/`usp_LogHealth`, бэкапы (`ops.usp_BackupDatabase` ZSTD/CHECKSUM/шифрование/URL, `usp_VerifyLastBackup`, `usp_RestoreScript`), задания Agent (Backup FULL/DIFF/LOG, CHECKDB, cleanup, Health report → `ops.HealthLog`), дрейф схемы (`ops.usp_SchemaSnapshot`/`usp_DriftCheck`, `drift-check.ps1`), Query Store baseline/compare, `MigrationRunner` + Testcontainers-режим тестов, tSQLt (`tests/tsqlt`, `tsqlt.ps1`), `Dockerfile` API + compose `--profile app`, GitHub Actions `ci.yml`, `reset-stand.ps1` | `sql/16-ops/010 … 050`, `scripts/tsqlt.ps1`, `scripts/drift-check.ps1`, `scripts/reset-stand.ps1`, `src/Waybill.Migrator/Migrator.cs`, `src/Waybill.Api/Dockerfile`, `docker-compose.yml`, [CI](.github/workflows/ci.yml), `docs/ops-notes.md` |
| 17 | Подписанные вебхуки магазинам (`crm.MerchantWebhook`, `ops.usp_ResolveOutboxTarget`, `usp_RecordWebhookResult`, HMAC в `OutboxDispatcher`), счета по ledger-тарифам (`bill.Invoice`, `bill.InvoiceLine` append-only, `usp_GenerateInvoice`/`usp_InvoiceReport`, `/merchants/{id}/invoices/*`), сквозная проверка `ops.usp_EndToEndCheck`, runbook (`ops.vw_RunbookStatus`, `usp_Runbook`), архитектура, чек-листы | `sql/17-final/010 … 040`, `src/Waybill.Data/Repositories/InvoiceRepository.cs`, `docs/architecture.svg`, `docs/runbook.md`, `docs/review-checklist.md`, `docs/migration-pitfalls.md` |

## Порядок применения

Папки `sql/NN-*` применяются по возрастанию номера, файлы внутри — по имени. Файлы с первой строкой `-- diagnostic: safe to re-run` содержат только `SELECT` и не меняют базу.

## Сброс стенда

```sql
USE master;
ALTER DATABASE Waybill SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE Waybill;
```

Контейнер: `docker compose down -v && docker compose up -d`.
