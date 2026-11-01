# Чек-лист code review для T-SQL (Waybill, глава 17)

Отметить в PR каждый применимый пункт; ссылка — на урок, где правило разобрано.

## Схема и типы (главы 3, 5, 6)
- [ ] Типы точные: `datetime2(3)`/`date`, `decimal(p,s)` для денег, `varchar` для ASCII-кодов с BIN2-коллацией там, где сравнение точное; никаких `float` для сумм, `nvarchar(max)` «на всякий случай».
- [ ] Именованные ограничения (`PK_`, `FK_`, `UQ_`, `CK_`, `DF_`); CHECK с `REGEXP_LIKE` для форматов; `json` — с `ISJSON`/`JSON_PATH_EXISTS` в CHECK.
- [ ] Вычисляемые столбцы для нормализованных ключей — `PERSISTED` и с индексом, если по ним ищут.
- [ ] Новая таблица с `MerchantId` — в политике RLS (`sec.MerchantIsolation`), с индексом, где `MerchantId` ведущий, и с правами ролям.
- [ ] PII — маска DDM / Always Encrypted; `DENY` для `waybill_api`, если чтение только через процедуры.

## Запросы (главы 2, 4, 9)
- [ ] SARGable предикаты: нет функций над столбцами в `WHERE`/`JOIN` (`CAST(col AS date)`, `UPPER(col)`, `ISNULL(col, …)`); ищут по persisted-вычисляемому.
- [ ] Нет `SELECT *` в модулях; список столбцов = контракт для Dapper.
- [ ] Keyset-пагинация вместо `OFFSET` на больших списках; `TOP (@n)` с параметром.
- [ ] Индекс под новый запрос есть или обоснованно нет (план приложен: seek, не scan; нет Key Lookup на горячем пути).
- [ ] Нет неявных преобразований типов параметров (`nvarchar` против `varchar` столбца — `DbString.IsAnsi`).
- [ ] Агрегаты по большим таблицам — на columnstore/витрине, `APPROX_*` где допустимо.

## Процедуры (главы 7, 8)
- [ ] `SET NOCOUNT ON; SET XACT_ABORT ON;`; ошибки — `THROW 5xxxx` с номером из `docs/errors.md` (добавить строку).
- [ ] Транзакция короткая, начинается как можно позже; `@ownTran` для вложенных вызовов; нет `BEGIN TRAN` без `COMMIT` в ветках.
- [ ] Набор строк — TVP/`INSERT … SELECT`, не цикл; батчи для массовых операций (5–20k, журнал!).
- [ ] Идемпотентность по внешнему ключу (`ExternalEventId`, `MessageId`); повтор — дубль, не ошибка.
- [ ] Outbox — через `ops.usp_EmitOutbox` внутри той же транзакции; никаких HTTP/почты из процедуры.
- [ ] Динамический SQL: идентификаторы — белый список + `QUOTENAME`, значения — параметры `sp_executesql`; ширина параметров не усекает ввод.
- [ ] Результат — фиксированная форма (столбцы, типы); изменение формы = изменение API-модели + тест.

## Конкурентность (глава 8)
- [ ] Не полагается на `SERIALIZABLE`/`HOLDLOCK` без нужды; горячие строки — `usp_UpdateShipmentIfMatch`/RowVer, счётчики — In-Memory.
- [ ] Порядок обращения к таблицам одинаков во всех процедурах (deadlock); retry на 1205 — в приложении.
- [ ] `READPAST`/`UPDLOCK`/`ROWLOCK` только в очередях; никаких `NOLOCK`.

## Миграция (глава 16)
- [ ] Файл в правильной папке с шагом номера; идемпотентен; применяется дважды; `PRINT` о пропуске внешних зависимостей.
- [ ] Изменение большой таблицы — метаданные/онлайн/батчи; expand/contract при несовместимом изменении.
- [ ] `GRANT` ролям в том же файле; `-- rollback:` комментарий.
- [ ] Тест: tSQLt для логики, xUnit для контракта; `docs/*.md` обновлены (`errors.md`, `*-notes.md`).

## Примеры «до / после» из курса
| До | После | Урок |
| --- | --- | --- |
| `WHERE CAST(OccurredAt AS date) = @d` | `WHERE OccurredAt >= @d AND OccurredAt < DATEADD(day, 1, @d)` | 4.2 |
| `WHERE UPPER(TrackingNumber) = @t` | `WHERE TrackingNumberNormalized = ship.fn_NormalizeTrackingNumber(@t)` | 3.6 / 6.2 |
| цикл `WHILE` по событиям с `INSERT` | один `INSERT … SELECT` из TVP с `NOT EXISTS` | 7.3 |
| `INSERT INTO ops.Outbox` руками | `EXEC ops.usp_EmitOutbox` (конверт, MessageId, проверка транзакции) | 11.6 |
| `ORDER BY ' + @col` | белый список из `sys.columns` + `QUOTENAME` | 15.8 |
| `DELETE FROM ops.WebhookInbox WHERE ReceivedAt < @d` | батчи `DELETE TOP (5000)` с паузой | 10.5 |
| `SELECT * FROM ship.Shipment` в API | процедура/список столбцов, `EXECUTE` на схему | 12.2 / 15.3 |
| `OFFSET @page * 50 ROWS` | keyset `(CreatedAt, ShipmentId) < (@before, @beforeId)` | 4.3 |
