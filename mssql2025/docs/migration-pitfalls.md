# Ловушки при переходе на SQL Server с PostgreSQL / MySQL / Oracle (глава 17)

| Тема | Привычка | В SQL Server 2025 | Где в курсе |
| --- | --- | --- | --- |
| Даты | `timestamp`/`timestamptz`, `now()` | `datetime2(3)` + `SYSUTCDATETIME()`; `datetimeoffset` только на границах; `AT TIME ZONE` с именами из `sys.time_zone_info`; `datetime` — не использовать | 2.6, 5.3 |
| Пустая строка vs NULL | Oracle: `''` = NULL | `''` — строка; `NULLIF(col, '')` на входе; `CONCAT` терпит NULL, `+` — нет | 2.4 |
| Регистр и коллации | PostgreSQL чувствителен к регистру | по умолчанию CI_AS: `'abc' = 'ABC'`; точные сравнения — BIN2-коллация столбца; `SC_UTF8` для `varchar` с UTF-8 | 3.2, 6.1 |
| Идентификаторы | `"quoted"`, snake_case, регистр | `[bracket]`/QUOTENAME; регистр — по коллации базы; схема всегда явно | 3.1 |
| Транзакции DDL | PostgreSQL: DDL транзакционен | DDL транзакционен, но не всё (`CREATE DATABASE`, full-text, `ALTER DATABASE`); мигратор без транзакции на файл — идемпотентность | 16.6 |
| LIMIT / OFFSET | `LIMIT 50 OFFSET 100` | `TOP (50)` / `OFFSET … FETCH` требует `ORDER BY`; keyset вместо OFFSET | 2.3, 4.3 |
| Пагинация «последняя страница» | `count(*) over()` | `COUNT(*) OVER ()` есть; дорого — отдельный `APPROX_COUNT_DISTINCT`/оценка | 9.6 |
| Upsert | `INSERT … ON CONFLICT`, `REPLACE` | `MERGE` с `HOLDLOCK` или «UPDATE, затем INSERT WHERE NOT EXISTS»; MERGE — с осторожностью и без триггерных сюрпризов | 7.4 |
| Автоинкремент | `serial`, `AUTO_INCREMENT`, sequences | `IDENTITY` (пропуски при откате — норма) или `SEQUENCE`; `SCOPE_IDENTITY()`/`OUTPUT inserted.*` | 3.3 |
| Boolean | `boolean` | `bit`; в `WHERE` — `= 1`, не `WHERE col` | 2.2 |
| Строки | `||`, `substr`, `regexp_*` | `CONCAT`/`+`, `SUBSTRING`, `REGEXP_LIKE/REPLACE/SUBSTR/SPLIT_TO_TABLE` (2025), `STRING_SPLIT … , 1` с ordinal | 6.x |
| JSON | `jsonb`, `->>` | тип `json` (2025), `JSON_VALUE`/`JSON_QUERY`/`OPENJSON WITH`, индексы по вычисляемым столбцам | 5.x |
| Массивы | `int[]`, `ANY(array)` | нет массивов: TVP, `STRING_SPLIT`, `OPENJSON`; `IN (SELECT value FROM …)` | 7.2 |
| Возвращаемые значения | `RETURNING` | `OUTPUT inserted./deleted.` (в переменную таблицу при триггерах/FK) | 7.5 |
| Функции | PL/pgSQL функции для всего | скалярные UDF — дорого (inline или TVF); процедуры для действий; `WITH SCHEMABINDING` | 7.6 |
| Блокировки чтения | MVCC по умолчанию | `READ COMMITTED` блокирующий по умолчанию → включить RCSI (+ADR); никаких `NOLOCK` | 8.1 |
| Deadlock | редки | обычны при разном порядке доступа; retry на 1205 обязателен | 8.5 |
| `GROUP BY` | всё, что не в агрегате | так же строго; `GROUPING SETS`, `PRODUCT` (2025) | 10.7 |
| `DISTINCT ON` | PostgreSQL | `ROW_NUMBER() OVER (PARTITION BY …) = 1` или `CROSS APPLY (SELECT TOP (1) …)` | 2.5 |
| Временные таблицы | `TEMP TABLE` на сессию | `#t` (сессия), `@t` (батч; без статистики — для малых), TVP; `tempdb` общий — Resource Governor | 2.7, 13.7 |
| `EXPLAIN` | текстовый план | `SET STATISTICS XML/IO ON`, Query Store, план в SSMS/ADS; `OPTION (RECOMPILE)` для sniffing | 9.x |
| Bulk load | `COPY` | `BULK INSERT` с форматом/ERRORFILE, `SqlBulkCopy`; минимальное логирование — по модели восстановления | 10.2, 16.1 |
| Секционирование | декларативные partition-таблицы | функция + схема, `SPLIT/MERGE/SWITCH`, выровненные индексы | 10.1 |
| Права | `GRANT ON ALL TABLES` | права на схему, ownership chaining, `EXECUTE AS`, RLS через `SESSION_CONTEXT` | 15.x |
| Бэкап | `pg_dump` логический | физический `BACKUP`/`RESTORE` с цепочкой журналов; `STOPAT` | 16.2 |
| `NULL` в уникальном индексе | несколько NULL допустимы | один NULL; фильтрованный индекс `WHERE col IS NOT NULL` | 4.4 |
| Целочисленное деление | `1/2 = 0.5` в MySQL | `1/2 = 0`; `1.0/2` или `CAST` | 2.2 |
| `ORDER BY` в подзапросе/представлении | сохраняется | не гарантируется; `TOP 100 PERCENT … ORDER BY` — не приём | 2.3 |
| Триггеры | построчные `FOR EACH ROW` | на инструкцию: `inserted`/`deleted` — наборы; логика set-based | 7.7 |
