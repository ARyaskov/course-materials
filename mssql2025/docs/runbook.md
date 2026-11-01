# Runbook обслуживания Waybill (глава 17)

Одна точка входа: `EXEC ops.usp_Runbook @Mode = 'check' | 'daily' | 'weekly', @DryRun = 1|0`. Задания Agent (главы 13, 16) выполняют те же шаги по расписанию; runbook — для ручного прогона, стенда без Agent и разбора инцидентов.

## Регламент

| Когда | Что | Процедура / объект | Норма (`ops.vw_RunbookStatus`) |
| --- | --- | --- | --- |
| каждые 15 мин | бэкап журнала | `ops.usp_BackupDatabase 'LOG'` | `backup-log` ≤ 30 мин |
| каждые 30 мин | здоровье: журнал, PVS, бэкапы, outbox, задания | `ops.usp_HealthReport` → `ops.HealthLog` | нет `error` |
| ежедневно 01:00 | полный бэкап + VERIFYONLY | `usp_BackupDatabase 'FULL'`, `usp_VerifyLastBackup` | `backup-full` ≤ 26 ч |
| ежедневно 02:00 | секции: SPLIT вперёд, SWITCH старых в архив | `ops.usp_MaintainEventPartitions @MonthsAhead = 2, @RetainMonths = 12` | `partitions` ≥ 1 |
| ежедневно 02:30 | эмбеддинги инцидентов | `ops.usp_EmbedPendingIncidents` в цикле (задание Agent) | `embeddings` = 0 |
| ежедневно 03:00 | чистка inbox / EventSeen | `ops.usp_PurgeInbox 90`, `usp_PurgeEventSeen 48` | — |
| ежедневно 05:00 | чистка бэкапов | `ops.usp_CleanupBackups` (`backup.retain_days`) | — |
| ежедневно 13:00 | разностный бэкап | `usp_BackupDatabase 'DIFF'` | — |
| еженедельно вс 04:00 | CHECKDB | `DBCC CHECKDB WITH DATA_PURITY` | без ошибок |
| еженедельно | индексы и статистика | `ops.usp_MaintainIndexes @DryRun = 0` (по фрагментации / возрасту статистики) | `index-frag` = 0, `stats-age` ≤ 7 |
| еженедельно | columnstore | `ALTER INDEX … REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON)` | — |
| еженедельно | витрина SLA (текущий + прошлый месяц) | `analytics.usp_RefreshCarrierSla` | — |
| еженедельно | ledger digest + проверка | `ops.usp_SaveLedgerDigest`, `usp_VerifyLedger` | verified |
| еженедельно | baseline Query Store | `ops.usp_QueryStoreBaseline 'weekly'` | — |
| после деплоя | снимок дрейфа, smoke, QS baseline | `drift-check.ps1 -Snapshot`, `080_deploy_checks.sql`, `usp_EndToEndCheck` | PASS |
| ежеквартально | восстановление на резервном сервере | `usp_RestoreScript` → RESTORE → CHECKDB | — |

## Размеры и пороги

* Журнал: 1 ГБ, рост 256 МБ; активность > 70 % или VLF > 200 — предупреждение (`ops.usp_LogHealth`).
* PVS > 2 ГБ или не убывает 30 мин — искать длинную транзакцию (`ops.vw_OldestTransactions`) / долгий читатель.
* Query Store: 1 ГБ, `READ_WRITE`; при > 80 % — чистка (`sp_query_store_remove_query` устаревших) или увеличение.
* tempdb: пул `waybill_background` ограничен `GROUP_MAX_TEMPDB_DATA_MB` (глава 13).
* Outbox: > 1000 в очереди — проверить диспетчер (`ops.vw_OutboxWorkers`), poison > 0 — `ops.vw_OutboxPoison` → разбор → `usp_RequeueOutbox`.

## Разбор типичных инцидентов

| Симптом | Куда смотреть | Действие |
| --- | --- | --- |
| API 503 «Busy» / таймауты | `ops.vw_Xe*` (главы 9), wait stats diff, `sys.dm_exec_requests` | блокировки: `ops.vw_OldestTransactions`; hot rows — глава 8 |
| Журнал растёт | `ops.vw_LogStatus.LogReuseWait` | `LOG_BACKUP` → задание; `ACTIVE_TRANSACTION` → сессия; `REPLICATION` → CDC/CES |
| События не попадают в таймлайн | `ops.RejectedEvent` (причины), `ops.WebhookInbox.Status` | формат/статус-мап (`ref.CarrierStatusMap`), окно `too-old` |
| Вебхуки магазину не приходят | `ops.vw_WebhookDeliveryStats`, `ops.vw_OutboxPoison`, `HealthLog` | `IsEnabled = 0` после 20 ошибок → починить URL → `UPDATE … IsEnabled = 1, FailedInRow = 0` |
| Медленный запрос после деплоя | `ops.tvf_QueryStoreCompare('deploy', 'after', 2.0)`, `ops.vw_QueryStoreRegressions` | force last good plan / hint (глава 9), затем правка |
| Дрейф схемы | `ops.usp_DriftCheck` | найти автора в аудите (`sec.tvf_AuditEvents`, `SCHEMA_OBJECT_CHANGE_GROUP`), вернуть скриптом |
| Ошибки прав 229/33504 | `sec.vw_RolePermissions`, `sec.vw_SecurityPolicies` | новая таблица без GRANT/RLS — правка `010_principals.sql` / политики |

## Восстановление после потери сервера

1. Экземпляр той же версии/коллации; `MSSQL_*`/`mssql-conf` как в compose.
2. DMK + сертификат TDE из файлов (`docs/security-notes.md`).
3. `RESTORE HEADERONLY`/`FILELISTONLY` → `RESTORE … WITH MOVE, NORECOVERY` по цепочке → `STOPAT` при необходимости → `RECOVERY`.
4. `15-security/010_principals.sql` (логины — пароли из секретов), `040_audit.sql`, задания (`13-async/040`, `16-ops/030`).
5. `07-procs/080_deploy_checks.sql`, `ops.usp_EndToEndCheck`, `usp_HealthReport`, `drift-check.ps1`.
6. Строки подключения API/симулятора → новый адрес; проверка `waybill.http`.
