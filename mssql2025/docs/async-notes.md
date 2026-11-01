# Асинхронность Waybill: заметки по главе 13

## Реестр механизмов

| Механизм | Что делает | Кто запускает | Где смотреть |
| --- | --- | --- | --- |
| `ops.Outbox` + `OutboxDispatcher` (Waybill.Api) | внешние доставки (webhook-и) | N воркеров API, партиции `AggregateId % 16` | `ops.vw_OutboxStats`, `vw_OutboxWorkers`, `vw_OutboxPoison`, метрики `waybill.outbox.*` |
| Service Broker (`//waybill/outbox/*`) | внутренние потребители событий | активация движка | `sys.conversation_endpoints`, `sys.transmission_queue`, `ops.BrokerErrorLog`, `sys.service_queues.is_receive_enabled` |
| `ops.EventSeen`, `ops.RateCounter` (In-Memory OLTP) | дедупликация, счётчики | ingest / API | `sys.dm_db_xtp_hash_index_stats`, `sys.dm_db_xtp_table_memory_stats` |
| Agent: 6 заданий категории Waybill | обслуживание, витрины, digest, снимки | Agent по расписанию | `msdb.dbo.sysjobhistory` |
| Resource Governor | приоритет API, ограничение фона, tempdb | классификатор `dbo.fn_WaybillClassifier` | `sys.dm_resource_governor_workload_groups` |

## Очередь outbox

* `ops.usp_DequeueOutbox @BatchSize, @LeaseSeconds, @WorkerId, @MaxAttempts, @PartitionCount, @Partition` — `@PartitionCount` делит 16; NULL — без партиций.
* `ops.usp_RequeueOutbox @OutboxId, @Reason` — вернуть poison после разбора.
* Индекс `IX_Outbox_Pending_Partition (Partition, CreatedAt, OutboxId) INCLUDE (...) WHERE ProcessedAt IS NULL`.
* Диспетчер: `Outbox:Workers` (делит 16), `BatchSize`, `LeaseSeconds` > время доставки пачки, backoff 1→5 с, poison после 10 попыток, `Webhooks` топик → URL (до главы 17).
* Два экземпляра API с одинаковыми партициями — допустимо (READPAST), порядок внутри партиции не гарантирован; строгий порядок — `Outbox:Partitions` + прикладная блокировка (задание 13.8).

## Service Broker

| Служба | Очередь | Активация | Readers | Назначение |
| --- | --- | --- | --- | --- |
| `//waybill/outbox/Initiator` | `ops.OutboxInitiatorQueue` | `ops.usp_OutboxInitiatorActivation` | 1 | закрытие диалогов, журнал ошибок |
| `//waybill/outbox/Target` | `ops.OutboxTargetQueue` | `ops.usp_OutboxTargetActivation` | 4 | внутренние потребители (`usp_ConsumeStatusChanged`, consumer `broker-internal`) |

Отправка — `ops.usp_SendOutboxMessage @OutboxId` внутри транзакции с `usp_EmitOutbox`. Ошибка потребителя → `ops.Outbox.LastError` + `END CONVERSATION WITH ERROR`; откатов `RECEIVE` нет по построению. `POISON_MESSAGE_HANDLING ON`, `RETENTION OFF`, `ENCRYPTION OFF` (одна база).

## In-Memory OLTP

* `FG_Memory` (`MEMORY_OPTIMIZED_DATA`) добавлена — **необратимо** для базы Waybill. `MEMORY_OPTIMIZED_ELEVATE_TO_SNAPSHOT = ON`.
* `ops.EventSeen` (SCHEMA_AND_DATA, hash 4M корзин), `ops.RateCounter` (SCHEMA_ONLY); native: `ops.usp_TryMarkEventSeen`, `ops.usp_IncrementCounter`; чистка `ops.usp_PurgeEventSeen` (задание Agent).
* Ошибки конфликтов 41301/41302/41305/41325 — повторять транзакцию (добавить в `SqlErrors`/`Resilience` — задание 13.5).
* Память: привязать базу к пулу с `MAX_MEMORY_PERCENT` (`sp_xtp_bind_db_resource_pool`) до роста таблиц.

## Задания Agent

| Задание | Расписание | Шаг |
| --- | --- | --- |
| Waybill - Partition maintenance | 1-го числа 02:00 | `usp_MaintainEventPartitions @MonthsAhead=2, @RetainMonths=12` под `job:partition-maintenance` |
| Waybill - Purge inbox | ежедневно 03:00 | `usp_PurgeInbox`, `usp_PurgeEventSeen` под `job:purge-inbox` |
| Waybill - Refresh CarrierSla | каждый час :15 | `usp_RefreshCarrierSla` текущий и прошлый месяц под `job:sla-recalc` |
| Waybill - Index maintenance | вс 01:00 | `usp_MaintainIndexes`, REORGANIZE NCCI/CCI под `job:maintain-indexes` |
| Waybill - Ledger digest | ежедневно 04:00 | `usp_SaveLedgerDigest`, `usp_VerifyLedger` |
| Waybill - Wait stats snapshot | каждые 5 мин | `usp_SnapshotWaitStats`, чистка 14 дней |

Оператор `waybill-ops`; оповещение severity 17+ в Waybill. Время расписаний — локальное время сервера. Владелец заданий на продакшене — `waybill_jobs`, не `sa`.

## Resource Governor

| Пул | CPU min/max/cap | Память | Группа | MAXDOP | Прочее |
| --- | --- | --- | --- | --- | --- |
| `waybill_api` | 30 / 100 / — | — | `waybill_api_wg` (HIGH) | экземпляр | grant ≤ 10 % |
| `waybill_background` | 0 / 30 / 50 | 40 % | `waybill_background_wg` (LOW) | 2 | grant ≤ 20 %, CPU ≤ 600 с, ≤ 16 запросов, tempdb ≤ 4 ГБ (2025) |

Классификатор: `APP_NAME()` `Waybill.Api%` → api; `Waybill.Simulator`, `Waybill.Migrator`, `SQLAgent%` → background; иначе default. `cost threshold for parallelism` = 50, `MAXDOP` = min(ядра, 8). Откат — `ALTER RESOURCE GOVERNOR DISABLE`.

## Замеры (заполнить на стенде)

| Замер | Значение |
| --- | --- |
| hot-rows 4×20×50: pending → 0 за (с), avg_delivery_ms при Workers=1 / 4 | |
| Брокер: задержка COMMIT → broker-internal (мс), 1 / 4 readers | |
| native vs disk (20 000 вызовов, мс) | |
| RG: p95 API под фоном, включён / выключен | |
