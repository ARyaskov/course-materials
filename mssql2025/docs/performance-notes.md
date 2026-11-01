# Производительность Waybill: заметки по главе 9

## Объём данных (005_seed_volume.sql)

| Таблица | Строк | Примечание |
| --- | --- | --- |
| ship.Address | ~5 005 | 5 000 сгенерированных получателей + ручной seed |
| ship.Shipment | ~50 003 | 3 перевозчика, 3 магазина, статусы с перекосом: DELIVERED ~70 %, LOST 1 %, CANCELLED 0,2 % |
| ship.TrackingEvent | ~230 000 | цепочки статусов по итоговому статусу отправления, шаг 6–36 ч |

Маркер применения — заказ `SEED-000001`; повторный запуск печатает `already applied`.

## Настройки экземпляра и базы

| Настройка | Значение | Где |
| --- | --- | --- |
| Query Store | READ_WRITE, AUTO, интервал 15 мин, 1 ГБ, wait stats ON | 010_query_store.sql |
| AUTOMATIC_TUNING | FORCE_LAST_GOOD_PLAN = ON | 010 |
| PARAMETER_SENSITIVE_PLAN_OPTIMIZATION, DOP/CE feedback, MGF persistence/percentile | ON | 010 |
| OPTIMIZED_SP_EXECUTESQL (2025) | ON | 010 |
| OPTIONAL_PARAMETER_PLAN_OPTIMIZATION (2025) | ON, если поддерживается сборкой | 010 (TRY/CATCH) |
| LAST_QUERY_PLAN_STATS | ON | 010 |
| blocked process threshold (s) | 5 | 020_xe_sessions.sql |
| cost threshold for parallelism | ≥ 25 рекомендовано (по умолчанию 5) | вручную, зафиксировать здесь: ___ |
| max degree of parallelism | по числу ядер NUMA-узла | вручную: ___ |

## Постоянные объекты диагностики

| Объект | Назначение |
| --- | --- |
| ops.vw_QueryStoreTop | топ запросов по CPU за 24 ч |
| ops.vw_QueryStoreRegressions | свежий план хуже предыдущего ≥ 2× (≥ 10 выполнений у обоих за 7 дней) |
| ops.vw_QueryStoreWaits | ожидания по планам из Query Store |
| ops.vw_QueryStoreForced | форсированные планы и неудачи форсирования |
| ops.WaitStatsSnapshot, ops.usp_SnapshotWaitStats, ops.tvf_WaitStatsDiff, ops.tvf_BenignWaits | снимки ожиданий и разность |
| XEvents: waybill_long_queries, waybill_timeouts, waybill_deadlocks, waybill_blocked | > 1 с, attention, deadlock graph, blocked process report |
| ops.vw_XeLongQueries, vw_XeTimeouts, vw_XeDeadlocks, vw_XeBlocked | чтение целей сессий |
| ops.usp_ShowExecutionModes @Tag | режимы операторов последнего фактического плана по метке в тексте |

## SLA-витрина

* `analytics.usp_RefreshCarrierSla @PeriodStart` — рабочая версия: SARGable диапазон по `IX_Shipment_CreatedAt_Report`, агрегат доставок по `NCCI_TrackingEvent` в batch mode, `APPROX_PERCENTILE_CONT`, `MERGE` в `analytics.CarrierSla`.
* `analytics.usp_RefreshCarrierSla_v1` — учебная «медленная» версия (функция на столбце, скалярная UDF `fn_DeliveryHours_v1` с `INLINE = OFF`, `PERCENTILE_CONT … OVER`). Не использовать в заданиях Agent.
* `analytics.usp_CarrierSlaReport @From, @To, @CarrierCode = NULL, @RegionCode = NULL` — чтение витрины; кандидат на OPPO.

### Замеры v1 / v2 (заполнить на стенде)

| Версия | CPU ms | elapsed ms | logical reads (Shipment / TrackingEvent / Worktable) | Query Store avg_duration_ms | avg_reads |
| --- | --- | --- | --- | --- | --- |
| v1 | | | | | |
| v2 | | | | | |

Ожидаемое отношение: CPU ~20×, чтения ~100×.

## Демонстрационные объекты (не для продакшена)

* `ship.usp_ShipmentsByStatus`, `_Recompile`, `_OptimizeFor` + `IX_Shipment_Status_CreatedAt` — parameter sniffing (015).
* `ship.tvf_ShipmentsByStatusMs` — multi-statement TVF для interleaved execution (035).
* Хинты Query Store из 050 снимаются в конце скрипта; проверка — `sys.query_store_query_hints` пуст.

## Чек-лист анти-паттернов (040_antipatterns.sql)

1. Функция на столбце в предикате → диапазон / вычисляемый столбец с индексом.
2. `nvarchar`-параметр против `varchar`-столбца → тип параметра на клиенте (`DbString IsAnsi`, `IsUnicode(false)`).
3. `OR` по разным столбцам → `UNION`.
4. `SELECT *` → явный список; JSON/LOB-столбцы только там, где нужны.
5. Скалярная UDF в `WHERE`/`SELECT` с `is_inlineable = 0` → inline TVF / соединение с агрегатом.
6. Курсор для вычислений → set-based; нужный курсор — `LOCAL FAST_FORWARD`.
7. `OFFSET` на глубоких страницах → keyset-пагинация.
8. Склейка значений в динамический SQL → `sp_executesql` с параметрами.

Регулярный контроль: блоки 1–5 скрипта 040 + `ops.vw_QueryStoreTop` с отношением `avg_reads / avg_rowcount`.
