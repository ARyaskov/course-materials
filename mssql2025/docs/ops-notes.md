# Эксплуатация Waybill: заметки по главе 16

## Журнал и восстановление

* `RECOVERY FULL`, ADR включён; проверка — `ops.vw_LogStatus` (занятость журнала, VLF, `log_reuse_wait_desc`, последний бэкап журнала), `ops.vw_PvsStats` (PVS), `ops.vw_OldestTransactions`; `ops.usp_LogHealth` печатает предупреждения с порогами.
* Пороги: активный журнал > 70 %, VLF > 200, PVS > 2 ГБ, транзакция > 5 мин, бэкап журнала старше 30 мин — в `ops.HealthLog` через `usp_HealthReport`.
* Батчи и миграции: в FULL журнал усекается только `BACKUP LOG` — большие операции делят на батчи (глава 10) и следят, чтобы задание `Backup LOG` работало во время миграции.

## Бэкапы (`020_backup_restore.sql`)

| Что | Как | Расписание |
| --- | --- | --- |
| FULL | `ops.usp_BackupDatabase 'FULL'` + `usp_VerifyLastBackup` | 01:00 |
| DIFF | `'DIFF'` | 13:00 |
| LOG | `'LOG'` | каждые 15 мин (RPO ≤ 15 мин) |
| Хранение | `ops.usp_CleanupBackups` (`backup.retain_days` = 14), история msdb 90 дней | 05:00 |
| CHECKDB | `DBCC CHECKDB WITH DATA_PURITY` | воскресенье 04:00 |

Сжатие `COMPRESSION (ALGORITHM = ZSTD, LEVEL = backup.zstd_level)` с откатом на MS_XPRESS; `CHECKSUM`; `MAXTRANSFERSIZE = 4 МБ`; шифрование сертификатом `WaybillTdeCert`, если он есть. Назначение — `InstanceDefaultBackupPath` (контейнер: том `waybill-backup`, `MSSQL_BACKUP_DIR`) или `backup.url` (S3-совместимое хранилище + credential с именем URL). `ops.vw_BackupHistory` — из msdb; `ops.BackupRun` — журнал вызовов с ошибками.

Восстановление: `EXEC ops.usp_RestoreScript @PointInTime = '…'` печатает последовательность `RESTORE … NORECOVERY` → `STOPAT` → `RECOVERY` в `Waybill_Restore` (MOVE из `sys.database_files`). На другом сервере — сначала сертификат TDE (глава 15). Проверка восстановления — часть CI (артефакт бэкапа) и ежеквартальный ручной прогон.

## Задания Agent (глава 13 + 16)

`Waybill - Backup FULL/DIFF/LOG`, `Integrity check`, `Backup cleanup`, `Health report` (каждые 30 мин → `ops.HealthLog`: журнал, бэкапы, outbox poison, упавшие задания). Без Agent (CI, Testcontainers) задания не создаются; бэкапы вызываются вручную.

## Дрейф схемы (`040_drift_check.sql`)

`ops.usp_SchemaSnapshot 'deploy'` в конце деплоя (`drift-check.ps1 -Snapshot`), `ops.usp_DriftCheck` сравнивает таблицы/индексы/модули/ограничения/права ролей `waybill_*`/маски/RLS/настройки; отличия — в `ops.HealthLog` и код возврата 1 (`drift-check.ps1`).

## Query Store как этап CI (`050_query_store_baseline.sql`)

`usp_QueryStoreBaseline 'before'` → нагрузка (тесты, smoke) → `'after'` → `tvf_QueryStoreCompare('before', 'after', 2.0)` — запросы, у которых длительность или чтения выросли вдвое; артефакт `qs-regressions.txt`. На стенде: `'deploy'` после каждого применения глав.

## Контейнеры

* `docker compose up -d` — база; `--profile app` — + `migrator` (одноразовый, `--skip 16-ops`) + `api` (Dockerfile, `Waybill__ConnectionString`), API ждёт `service_completed_successfully`.
* Ограничения Linux/контейнера: нет FILESTREAM, нет Windows-аутентификации, `xp_cmdshell`/`xp_delete_file` работают, пути — `/var/opt/mssql/...`; `BULK INSERT` — с тома `/import`; Agent — `MSSQL_AGENT_ENABLED=true`.
* Testcontainers: `WAYBILL_TEST_MODE=container` — `DatabaseFixture` поднимает `mssql/server:2025-latest`, применяет `sql/**` через `MigrationRunner` (без `16-ops`), тесты идут против него; локальный режим — существующая база.

## Миграции

`Waybill.Migrator`/`apply.ps1`: лексикографический порядок `NN-name/NNN_file.sql`, `GO`-пакеты, журнал `dbo.SchemaMigrations` (имя + SHA-256), `--only`/`--skip`/`--force`. Правила: скрипт идемпотентен (`IF NOT EXISTS`, `CREATE OR ALTER`); expand/contract для несовместимых изменений; онлайн-операции (`ONLINE = ON`, `RESUMABLE`) для больших таблиц; без транзакции на весь файл — каждый пакет сам за себя, повторный прогон чинит.

## tSQLt

`scripts/tsqlt.ps1 -Install` (скачивает с tsqlt.org, `PrepareServer.sql` включает CLR — sysadmin), `scripts/tsqlt.ps1` применяет `tests/tsqlt/*.sql` и `RunAll`, результат `tests/tsqlt/results.xml` (JUnit). Ограничение: `FakeTable` не применяется к temporal-таблицам под schema-bound RLS (`ship.Shipment`) — такие тесты работают с реальными таблицами внутри откатываемой транзакции.

## CI (`.github/workflows/ci.yml`)

Сервис-контейнер SQL Server 2025 → build → migrate (`--skip 16-ops`) → `16-ops` → QS baseline → `dotnet test` → tSQLt → smoke API (health, webhook, timeline, sorted) → QS compare → drift check → COPY_ONLY бэкап → артефакты (trx, results.xml, qs-regressions.txt).

## Прогон на живом стенде (2026-09-17)

Стенд: SQL Server 2025 17.0.1135.8 Enterprise Evaluation, Windows-аутентификация, коллация экземпляра `Cyrillic_General_CI_AS`, база `Latin1_General_100_CI_AS_SC_UTF8`. `scripts/reset-stand.ps1 -Force` проходит целиком; `ops.usp_EndToEndCheck` — PASS 10/10. Ограничения стенда и решения, которые попали в скрипты:

| Ограничение | Где проявилось | Решение в проекте |
| --- | --- | --- |
| Agent остановлен | `13-async/040`, `16-ops/030` | задания создаются идемпотентно, выполнение — `ops.usp_Runbook` вручную; `usp_HealthReport` отмечает `agent stopped` |
| Full-Text не установлен | `06-strings/040`, `14-ai/040` | `CONTAINSTABLE` собирается динамически через `sp_executesql` при наличии индекса, иначе `LIKE`-fallback |
| `EDIT_DISTANCE*`/`JARO_WINKLER*` требуют `PREVIEW_FEATURES = ON` | `06-strings/030` | скрипт включает опцию базы; сходства — `int` 0–100, пороги подобраны под это |
| `rowversion` в temporal-истории | `11-history/010` | `ship.ShipmentHistory` — rowstore с PAGE-сжатием (35343 при CCI); retention ставится после индексов (13765) |
| Native-модули под UTF8-коллацией не принимают `varchar`-литералы, `DATETRUNC`, `IF EXISTS (подзапрос)` | `13-async/030` | ключи `nvarchar(64) COLLATE Latin1_General_100_BIN2`, `N''`-литералы, `SELECT COUNT(*)` вместо `EXISTS` |
| Ошибки компиляции (468 коллации, 37359 ledger, 10609 фильтрованный индекс по вычисляемому столбцу) не ловятся `TRY/CATCH` в том же пакете | демо-фрагменты глав 2, 4, 11 | `sp_executesql` внутри `TRY` |
| Тип `json` без неявного преобразования в `nvarchar` для `INSERT … EXEC` | `usp_GetShipmentTimeline`, Simulator | процедура отдаёт `CAST(… AS nvarchar(max))` |
| 13535 (конкурентное обновление temporal-строки) | Simulator `hot`, ingest | классифицируется как повторяемая (`Resilience.IsDeadlock`), retry с джиттером |
| Бэкапы пересозданной базы | `16-ops/020` | `ops.vw_BackupHistory` и `usp_VerifyLastBackup` фильтруют `backupset` по `database_guid` текущей базы |
| `BULK INSERT` от имени службы | `10-bulk/020` | каталогу `data/` выдан `Modify` для `NT SERVICE\MSSQLSERVER`; ошибки 4863–4867 из `ERRORFILE` перехватываются в `TRY/CATCH` |
