# История изменений Waybill: заметки по главе 11

## Матрица механизмов на ship.Shipment

| Механизм | Что фиксирует | Потребитель | Задержка | Стоимость записи | Обслуживание |
| --- | --- | --- | --- | --- | --- |
| Temporal (`ship.ShipmentHistory`) | каждое состояние строки + `ModifiedBy` | поддержка («как было»), API (лента версий) | синхронно | вставка в историю (rowstore, PAGE) на каждый UPDATE/DELETE | retention 24 мес; чек-лист миграций |
| Change Tracking | ключ + версия + операция + маска столбцов | поисковый индекс, кэш карточек | синхронно (pull) | низкая | retention 3 дня; контроль отставания потребителей (`ops.SyncCursor`) |
| CDC (`ship_Shipment`) | каждое изменение до/после по LSN | ETL в хранилище, внешние коннекторы | секунды (Agent) | асинхронно из журнала | Agent jobs; retention; второй capture instance при смене схемы; журнал при остановке capture |
| Outbox (`ops.Outbox`) | бизнес-события (`shipment.*`) | webhook-и магазинам, внутренние потребители | опрос ~1 с + доставка | INSERT в той же транзакции | диспетчер, poison, чистка `OutboxDelivery` |
| CES (`waybill-shipments`) | изменение строки → CloudEvents в Event Hubs | витрины реального времени, внешние системы | секунды | чтение журнала | preview; credential; `sys.dm_change_feed_errors`; журнал при остановке группы |

`bill.Tariff` (append-only) и `bill.Surcharge` (updatable) — ledger; digest → `ops.LedgerDigest` (стенд) / внешнее хранилище (продакшен); проверка `ops.usp_VerifyLedger` по расписанию.

## Правила для кода

1. `ModifiedBy`: API кладёт пользователя в `SESSION_CONTEXT('user')`; операторские процедуры пишут `ModifiedBy = DEFAULT`, ingest — `'ingest:<CarrierCode>'`.
2. Обновлять только изменившиеся значения (`WHERE … IS DISTINCT FROM …`): каждая версия — строка в истории, версия CT, строка CDC.
3. Бизнес-события — только через `ops.usp_EmitOutbox` внутри транзакции с данными (50080 иначе). Ingest пишет outbox напрямую тем же конвертом.
4. Потребители outbox/CT/CDC/CES — идемпотентны: по `MessageId` (`ops.OutboxDelivery`), по ключу (CT), по `id` события (CES).
5. `ship.TrackingEvent` — без temporal, CT, CDC (секционирование и `SWITCH`).
6. Temporal-миграции с `SYSTEM_VERSIONING = OFF` — одна транзакция `OFF → ALTER обеих → ON` с явным retention.
7. Ledger-схема `bill`: только `ADD COLUMN`; исправление — новая строка, не правка.

## Чек-лист temporal для миграций

- столбцы периода `datetime2(3) HIDDEN`; история `<Table>History` в той же схеме; retention явно
- история: rowstore с PAGE-сжатием (columnstore невозможен: rowversion/json в строке) + индекс `(ключ, ValidTo, ValidFrom)`
- после восстановления базы: `is_temporal_history_retention_enabled = 1`
- drift-check сравнивает `temporal_type`, историю, retention, индексы истории

## Объекты главы

| Объект | Назначение |
| --- | --- |
| `ship.tvf_ShipmentAsOf(@ShipmentId, @AsOf)` | состояние на момент (UTC) |
| `ship.tvf_ShipmentVersions(@ShipmentId)` | версии с флагами изменённых полей |
| `ship.tvf_StatusChangeAudit(@From, @To)` | смены статуса за период: кто, из какого в какой |
| `ops.usp_GetShipmentChanges` / `usp_AckShipmentChanges` | CT-потребитель с курсором и полной пересинхронизацией |
| `ops.usp_GetShipmentCdcChanges` / `usp_AckShipmentCdcChanges` | CDC-потребитель по LSN (при включённом CDC) |
| `bill.tvf_TariffFor(@CarrierId, @RegionId, @WeightGrams, @AsOf)` | действующая ставка |
| `ops.usp_SaveLedgerDigest` / `usp_VerifyLedger` | digest и проверка цепочки |
| `ops.usp_EmitOutbox` | запись бизнес-события (CloudEvents-конверт, `MessageId`) |
| `ops.usp_ConsumeStatusChanged` | пример идемпотентного потребителя (`ops.OutboxDelivery`) |
| `ops.vw_OutboxStats`, `ops.tvf_OutboxByAggregate` | наблюдение за очередью |

## Замеры (заполнить на стенде)

| Замер | Значение |
| --- | --- |
| hot-rows 4×20×50: events/s без механизмов (глава 8) / с temporal+CT / +CDC | |
| Версий в истории на транзакцию ingest | |
| Размер `ship.ShipmentHistory` после прогона (строк, МБ, row groups) | |
| CDC latency (`sys.dm_cdc_log_scan_sessions`) | |
| Outbox: avg_delivery_ms, poison после прогона диспетчера | |
| `usp_VerifyLedger` — время проверки | |
