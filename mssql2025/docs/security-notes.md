# Безопасность Waybill: заметки по главе 15

## Роли и учётки

| Роль базы | Кто | Права |
| --- | --- | --- |
| `waybill_api` | сервисная учётка API (login `waybill_api` → user `waybill_api_svc`) | EXECUTE на `ops`/`ship`/`analytics`, SELECT `ref`/`crm`, точечные SELECT/INSERT на таблицы репозиториев (`ship.Shipment`, `ops.Incident`, `ops.Outbox*`, `ops.EventImportRaw`), `DENY SELECT ship.Address` |
| `waybill_ingest` | та же учётка API | обход RLS без контекста — только для маршрутов приёма событий |
| `waybill_readonly` | аналитики, поддержка (`waybill_reader` login) | SELECT прикладных схем, `SHOWPLAN`; PII маскируется; `DENY` записи в `ship` |
| `waybill_ops` | эксплуатация | readonly + EXECUTE/SELECT `ops`, `VIEW DATABASE STATE`, `UNMASK` |
| `waybill_merchant_test`, `waybill_reader_test` | пользователи без логина | `EXECUTE AS` в скриптах и тестах |

Пароли логинов в `010_principals.sql` — для стенда. Прод: секреты из хранилища, `CHECK_POLICY = ON`, ротация; Entra ID через Azure Arc там, где доступно.
Строка подключения API под сервисной учёткой: `Server=…;Database=Waybill;User ID=waybill_api;Password=…;Encrypt=Strict` (переменная `Waybill__ConnectionString`). На стенде с Integrated Security под sysadmin RLS не фильтрует (`db_owner` в списке обхода) — проверять через `EXECUTE AS` или под `waybill_api`.

## RLS (`020_rls.sql`)

* Предикат `sec.fn_MerchantPredicate(MerchantId)`: контекст задан → только свой магазин; не задан → всё, но только `waybill_ingest`/`waybill_readonly`/`db_owner`.
* Политика `sec.MerchantIsolation`: FILTER + BLOCK (INSERT/UPDATE) на `ship.Shipment`, `ship.Address`, `ops.Incident`, `ship.RecipientContact`; FILTER на `ship.ShipmentHistory`. `ship.TrackingEvent` — через процедуры (соединение с `ship.Shipment`).
* Контекст: `sec.usp_SetMerchantContext` / `SessionContext.SetMerchantAsync` — `sp_set_session_context 'MerchantId', @read_only = 1`. Пул соединений сбрасывает контекст (`sp_reset_connection`).
* API: заголовок `X-Merchant-Id` (до аутентификации; затем claim токена) → `IDbConnectionFactory.OpenAsync(user, merchantId)` в merchant-scoped репозиториях (timeline, list, sorted, incidents search/similar).
* Выключение: `ops.Setting 'security.rls' = 0` + повторный прогон `020`.
* Ошибка 33504 (BLOCK) → HTTP 403.

## Маскирование (`030_masking.sql`)

`ship.Address.Phone` partial, `RecipientName`/`Apartment` default, `crm.Merchant.ContactEmail` email, `ContactPhone` partial. `UNMASK`: `waybill_ops` на схемы `ship`/`crm`, `waybill_api` на `ship.Address`. DDM не защищает от вывода предикатами и не является шифрованием.

## Шифрование (`035_encryption.sql`)

* Always Encrypted: `ship.RecipientContact` (Phone/Email BIN2 под детерминированное, Note — под случайное). CMK создаётся при `security.ae.cmk_path`; CEK и шифрование столбцов — клиентом (модуль SqlServer: `New-SqlColumnEncryptionKey`, `Set-SqlColumnEncryption`). Клиент: `Column Encryption Setting=Enabled` в строке подключения.
* TDE: `security.tde = 1` → DMK master + `WaybillTdeCert` (бэкап в InstanceDefaultBackupPath: `.cer` + `.pvk`) + DEK AES_256. Пароли DMK/PVK — стенд; в проде — в сейф вместе с файлами сертификата. `sec.vw_TdeStatus`.
* Бэкап с шифрованием: `BACKUP DATABASE Waybill … WITH ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = WaybillTdeCert)` (глава 16).

## Аудит (`040_audit.sql`)

Server audit `Waybill_Audit` → `InstanceDefaultLogPath\WaybillAudit\*.sqlaudit` (20 × 100 МБ). Серверная спецификация: неудачные логины, изменения принципалов/ролей/прав/аудита. Спецификация базы: SELECT `ship.Address`/`ship.RecipientContact`, EXECUTE `sec`, изменения схемы/ролей/прав/имперсонация. Чтение — `sec.tvf_AuditEvents(@Since)`, `sec.vw_AuditPiiReads` (нужен `CONTROL SERVER` для `fn_get_audit_file`). Выключение — `security.audit = 0`.

## Динамический SQL (`050_injection.sql`)

`ship.usp_ListShipmentsSorted`: белый список столбцов из `sys.columns`, `QUOTENAME`, направление из двух значений, значения — параметры `sp_executesql`, экранирование `LIKE`. Ошибки 50095/50096 → 400. Эндпоинт `GET /merchants/{id}/shipments/sorted`.
