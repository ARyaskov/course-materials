# Массовые данные Waybill: заметки по главе 10

## Секционирование ship.TrackingEvent

* Функция `pf_MonthlyEvents (datetime2(3)) RANGE RIGHT`, границы — первые числа месяцев от 2026-01-01; схема `ps_MonthlyEvents ALL TO ([FG_Events])`.
* Все индексы выровнены (на схеме): `PK_TrackingEvent (OccurredAt, EventId)`, `IX_TrackingEvent_Shipment_OccurredAt`, `IX_TrackingEvent_OccurredDate_Status`, `UQ_TrackingEvent_Carrier_External`, `NCCI_TrackingEvent`.
* **Компромисс:** `UQ_TrackingEvent_Carrier_External` = `(CarrierId, ExternalEventId, OccurredAt)`. Уникальность внешнего идентификатора события гарантируется ограничением только в пределах одного `OccurredAt`; полную защиту от дублей обеспечивает `ops.usp_IngestTrackingEvents` (`NOT EXISTS … WITH (UPDLOCK, HOLDLOCK)` по `(CarrierId, ExternalEventId)`). Прямые вставки в таблицу в обход процедуры запрещены (глава 15 — права только на процедуры).
* Запросы по `ShipmentId` без предиката по `OccurredAt` обходят все секции (по 2–3 чтения на секцию) — приемлемо; `OccurredDate` не даёт partition elimination.
* Change tracking / CDC на `ship.TrackingEvent` не включать (`SWITCH` несовместим).

## Горячее окно и архив

| Объект | Назначение |
| --- | --- |
| `ship.TrackingEvent` | горячие события, окно `@RetainMonths` (продакшен: 12) |
| `ship.TrackingEventStage` | копия структуры на той же схеме; только для `SWITCH`; всегда пуст вне обслуживания |
| `ship.TrackingEventArchive` | ordered clustered columnstore по `OccurredAt`, не секционирован |
| `ship.vw_TrackingEventAll` | `UNION ALL` горячей таблицы и архива; для запросов «за всё время» |
| `ops.usp_MaintainEventPartitions @MonthsAhead, @RetainMonths, @DryRun` | SPLIT вперёд → SWITCH+INSERT в архив+TRUNCATE stage → MERGE левых пустых границ → REORGANIZE архива |

Расписание (глава 13): 1-го числа месяца, под `job:partition-maintenance`. Сначала `@DryRun = 1` и журнал плана.

События старше горячего окна отклоняются на входе: `usp_MaintainEventPartitions` записывает нижнюю границу в `ops.Setting ('ingest.hot_window_start')`, `usp_IngestTrackingEvents` классифицирует такие события как `too-old`.

## Загрузка файлов

* `ops.Setting ('import.root')` — корень импорта: `/import` в контейнере (`./data` смонтирован), `C:\Waybill\data` по умолчанию на Windows-экземпляре. Скопируйте туда содержимое папки `data` проекта или измените `import.root` на свой серверный путь. Учётная запись SQL Server должна иметь право чтения. Проверить: `SELECT * FROM ops.Setting`.
* Демонстрация главы 5 (`025_json_read_demo.sql`) читает `/import/webhooks/` в контейнере или `C:\Waybill\data\webhooks\` на Windows; при другом размещении поправьте `@dir` в начале этого скрипта.
* `ops.usp_ImportEventFile @CarrierCode, @FileName, @DryRun` — `BULK INSERT` (CSV, UTF-8, `FIRSTROW = 2`, `TABLOCK`, `MAXERRORS = 10`, `ERRORFILE` с меткой времени) в heap `ops.EventImportRaw` → журнал `ops.EventImport` → TVP → `ops.usp_IngestTrackingEvents`.
* `ops.usp_ImportWebhookFile @CarrierCode, @FileName` — `OPENROWSET(BULK … SINGLE_CLOB)` → `ops.usp_ReceiveWebhook`.
* Права: `ADMINISTER BULK OPERATIONS` — только у роли загрузчика/задания Agent, не у API.
* Файлы `*.errors`, `*.errors.Error.Txt` рядом с исходным; в `.gitignore`.

## Чистка

* `ops.usp_PurgeInbox @OlderThanDays = 90, @BatchSize = 5000, @MaxBatches, @PauseMs, @MaxLogPercent` — processed/duplicate документы и их `RejectedEvent`; останавливается при заполнении журнала.
* `ship.usp_RecomputeLastEventAt @BatchSize` — пересчёт по диапазонам ключа, только изменившиеся строки.
* Индексы под чистку: `IX_WebhookInbox_ReceivedAt (ReceivedAt) INCLUDE (Status)`, `IX_RejectedEvent_Inbox (InboxId)`.

## Генератор

`050_generate_events.sql`: +200 000 отправлений (`GEN-`), ~930 000 событий, батчи по 20 000 отправлений в своей транзакции, детерминированные распределения, маркер идемпотентности `GEN-000001`. Итоговый объём после главы: ~250 000 отправлений, > 1 100 000 событий.

## Замеры (заполнить на стенде)

| Замер | Значение |
| --- | --- |
| Генерация: время / max active_log_size_mb | |
| Секции после генерации (строк по месяцам) | |
| SWITCH секции (мс) | |
| INSERT секции в архив (с, строк) | |
| TRUNCATE секции stage (мс) | |
| MERGE (мс) | |
| DELETE того же объёма батчами (с, журнал МБ) — на копии | |
| Размер архива CCI / тех же строк в rowstore (МБ) | |
| Segment reads/skipped: архив за месяц; vw_TrackingEventAll за месяц | |
| APPROX_COUNT_DISTINCT vs COUNT DISTINCT: время, ошибка % | |
