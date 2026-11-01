# Конкуренция в Waybill: заметки по главе 8

## Настройки базы

| Параметр | Значение | Зачем |
| --- | --- | --- |
| `READ_COMMITTED_SNAPSHOT` | ON | читатели не ждут писателей; API и отчёты не блокируют ingest |
| `ALLOW_SNAPSHOT_ISOLATION` | ON | отчёты, которым нужна согласованность нескольких запросов (`SET TRANSACTION ISOLATION LEVEL SNAPSHOT`) |
| `ACCELERATED_DATABASE_RECOVERY` | ON | мгновенный откат, PVS; обязателен для optimized locking |
| `OPTIMIZED_LOCKING` | ON | одна XACT-блокировка на транзакцию, lock after qualification |

Проверка: `sql/08-concurrency/010_optimized_locking.sql`.

## Правила для кода

1. Транзакция — на сервере, короткая, без round-trip к клиенту внутри.
2. `SET XACT_ABORT ON` в каждой процедуре, которая пишет. `THROW`, не `RAISERROR`.
3. «Прочитал — решил — обновил» под RCSI обязан читать с `UPDLOCK` (`, HOLDLOCK` — если проверяется отсутствие строки), либо делать проверку предикатом `UPDATE`.
4. Порядок обращения к таблицам в пишущих процедурах фиксирован: `ship.TrackingEvent` → `ship.Shipment` → `ops.Outbox` → `ops.WebhookInbox`. Новые процедуры следуют тому же порядку.
5. Deadlock (1205) — ретрай на клиенте: до 3 попыток, пауза 50·2ⁿ мс с джиттером; на сервере ретрай только в утилитарных обёртках.
6. Пользовательское редактирование — оптимистично (`RowVer`/ETag, 50070 → 412). Серверные процессы — блокировки и атомарные `UPDATE`.
7. Хинты допустимы только в очередях (`READPAST, UPDLOCK, ROWLOCK`) и в «прочитал — обновил» (`UPDLOCK`). `NOLOCK` не используется.

## Очередь outbox

* `ops.usp_DequeueOutbox @BatchSize, @LeaseSeconds, @WorkerId, @MaxAttempts` — атомарный захват пачки: `TOP (n)` по `IX_Outbox_Pending`, `WITH (READPAST, UPDLOCK, ROWLOCK)`, `UPDATE … OUTPUT inserted.*`. Запись считается свободной, если `ProcessedAt IS NULL AND (LockedUntil IS NULL OR LockedUntil < now) AND Attempts < @MaxAttempts`.
* `ops.usp_CompleteOutbox @Ids, @WorkerId` — отмечает доставленные записи; чужие аренды не трогает.
* `ops.usp_FailOutbox @OutboxId, @WorkerId, @Error` — фиксирует ошибку и откладывает повтор: `LockedUntil = now + 30с × Attempts`.
* `ops.vw_OutboxPoison` — записи с `Attempts >= 10`; их dequeue не берёт, решение принимает человек.
* Истечение аренды во время доставки = возможная повторная доставка. Потребители обязаны быть идемпотентными по `OutboxId`.

## Прикладные блокировки: реестр имён

| Ресурс | Режим / владелец | Кто берёт | Смысл |
| --- | --- | --- | --- |
| `job:maintain-indexes` | Exclusive / Session | `ops.usp_RunExclusive` | одно обслуживание индексов за раз |
| `job:sla-recalc` | Exclusive / Session | пересчёт `analytics.CarrierSla` (глава 13) | один пересчёт за раз |
| `order:<MerchantCode>:<ExternalOrderId>` | Exclusive / Transaction, таймаут 5 с | `ship.usp_CreateShipmentSerialized` | второй запрос ждёт и получает существующее отправление вместо 2627 |
| `outbox-dispatcher:<topic>` | Exclusive / Session | диспетчер outbox (глава 13) для топиков с порядком доставки | один экземпляр на топик |
| `ref:carrier-status-map` | Shared (читатели кэша) / Exclusive (изменение) / Transaction | приложение при перезагрузке кэша, миграции справочника | согласованность кэша и базы |

Правила: префикс по назначению, без пробелов, регистр значим, длина ≤ 255. Новое имя — добавить в таблицу.

## Оптимистичная конкуренция

* `ship.Shipment.RowVer rowversion` — версия строки, меняется движком при любом `UPDATE`.
* `ship.usp_GetShipmentVersion @ShipmentId, @RowVer OUTPUT, @ETag OUTPUT` — версия для `If-None-Match` (304).
* `ship.usp_UpdateShipmentIfMatch @ShipmentId, @ExpectedRowVer, …, @NewRowVer OUTPUT` — `UPDATE … WHERE RowVer = @ExpectedRowVer`; 0 строк → 50001 (нет строки) или 50070 (изменена, HTTP 412).
* ETag = `BASE64_ENCODE(RowVer)`; в C# — `Convert.ToBase64String(byte[8])`.
* Инкрементальная выгрузка по `RowVer > @lastSeen` — только с верхней границей `MIN_ACTIVE_ROWVERSION()`.

## Диагностика

| Скрипт | Что показывает |
| --- | --- |
| `000_transactions_demo.sql` | `@@TRANCOUNT`, savepoint, обречённая транзакция, `XACT_STATE()` |
| `040_deadlock_demo.sql` | сценарий deadlock, чтение графов из `system_health`, обёртка с ретраем |
| `045_long_transactions.sql` | активные транзакции по возрасту, журнал (`sys.dm_db_log_stats`), PVS (`sys.dm_tran_persistent_version_store_stats`), snapshot-транзакции |
| `060_blocking_monitor.sql` | блокировки по сессиям, цепочки блокировок, эскалации, `LCK_M_*` в wait stats |
| `070_hot_rows_demo.sql` | однопоточное воспроизведение горячей строки |
| `scripts/hot-rows.ps1` | параллельная нагрузка на одно отправление |

## Результаты прогонов hot-rows.ps1

Заполняется после запуска на стенде (`./scripts/hot-rows.ps1 -Workers 8 -Batches 20 -BatchSize 50`).

| Режим | Workers×Batches×Size | events/s | retries (1205) | max LCK wait ms | эскалации | KEY-locks на пакет |
| --- | --- | --- | --- | --- | --- | --- |
| optimized locking ON | 8×20×50 | | | | 0 | 0 (XACT) |
| optimized locking OFF | 8×20×50 | | | | 0 | ~50–150 |
| optimized locking OFF | 8×4×5000 | | | | >0 | эскалация |

Инвариант каждого прогона: число вставленных `hot-*` событий равно `Workers × Batches × BatchSize`.
