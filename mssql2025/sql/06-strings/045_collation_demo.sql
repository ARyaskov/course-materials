-- diagnostic: safe to re-run
/*
  045_collation_demo.sql — коллации: сортировка, регистрозависимый seek, конфликт коллаций, UTF-8 против UTF-16 (урок 6.4).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Три порядка сортировки
SELECT City, 'database' AS collation_used FROM (VALUES (N'Орёл'), (N'Орел'), (N'Москва'), (N'Самара'), (N'Йошкар-Ола'), (N'Ижевск')) AS t(City) ORDER BY City;
SELECT City, 'Cyrillic_CI_AI' FROM (VALUES (N'Орёл'), (N'Орел'), (N'Москва'), (N'Самара'), (N'Йошкар-Ола'), (N'Ижевск')) AS t(City) ORDER BY City COLLATE Cyrillic_General_100_CI_AI;
SELECT City, 'BIN2' FROM (VALUES (N'Орёл'), (N'Орел'), (N'Москва'), (N'Самара'), (N'Йошкар-Ола'), (N'Ижевск')) AS t(City) ORDER BY City COLLATE Latin1_General_100_BIN2;
GO

-- 2. Регистрозависимый столбец с индексом: seek
DROP TABLE IF EXISTS demo.CityCs;
CREATE TABLE demo.CityCs (Id int IDENTITY PRIMARY KEY, Name nvarchar(100) COLLATE Latin1_General_100_CS_AS NOT NULL, INDEX IX_CityCs_Name (Name));
INSERT INTO demo.CityCs (Name) SELECT City FROM demo.Shipment;
SET STATISTICS IO ON;
SELECT COUNT(*) FROM demo.CityCs WHERE Name = N'Москва';   -- seek, регистр учитывается
SELECT COUNT(*) FROM demo.CityCs WHERE Name = N'москва';   -- seek, 0 строк
SET STATISTICS IO OFF;
DROP TABLE demo.CityCs;
GO

-- 3. Конфликт коллаций: BIN2-столбец против переменной/временной таблицы
DECLARE @code varchar(16) = 'FASTEX';                         -- коллация базы (CI)
SELECT Name FROM ref.Carrier WHERE Code = @code;              -- ок: переменная приводится к коллации столбца
DROP TABLE IF EXISTS #codes;
CREATE TABLE #codes (Code varchar(16));                       -- коллация tempdb
INSERT INTO #codes VALUES ('FASTEX');
BEGIN TRY
    -- ошибка 468 — ошибка компиляции, TRY того же пакета её не ловит: динамический SQL компилируется отдельно
    EXEC sys.sp_executesql N'SELECT c.Name FROM ref.Carrier AS c JOIN #codes AS t ON t.Code = c.Code;';
    PRINT 'no conflict: instance collation compatible';
END TRY
BEGIN CATCH
    PRINT CONCAT('conflict: ', ERROR_MESSAGE());
END CATCH;
SELECT c.Name FROM ref.Carrier AS c JOIN #codes AS t ON t.Code COLLATE Latin1_General_100_BIN2 = c.Code;   -- явный COLLATE
DROP TABLE #codes;
CREATE TABLE #codes2 (Code varchar(16) COLLATE Latin1_General_100_BIN2);                                  -- совпадающая коллация
INSERT INTO #codes2 VALUES ('FASTEX');
SELECT c.Name FROM ref.Carrier AS c JOIN #codes2 AS t ON t.Code = c.Code;
DROP TABLE #codes2;
GO

-- 4. UTF-8 против UTF-16 на адресах
SELECT SUM(DATALENGTH(CAST(Street AS varchar(200)))) AS utf8_bytes, SUM(DATALENGTH(Street)) AS utf16_bytes, COUNT(*) AS rows_
FROM ship.Address;

-- 5. Столбцы с коллацией, отличной от коллации базы (ожидаются только BIN2-коды)
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS table_name, c.name, c.collation_name
FROM sys.columns AS c
WHERE c.collation_name IS NOT NULL AND c.collation_name <> CAST(DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS nvarchar(128))
  AND OBJECTPROPERTY(c.object_id, 'IsUserTable') = 1 AND OBJECT_SCHEMA_NAME(c.object_id) <> N'demo';
GO
