-- diagnostic: safe to re-run
/*
  070_null_collation_demo.sql — NOT IN с NULL, ISNULL/COALESCE, конфликт коллаций, регистр в трек-номерах (урок 2.6).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. NOT IN с NULL в подзапросе → 0 строк; NOT EXISTS → ожидаемое число
SELECT COUNT(*) AS not_in_rows
FROM demo.Shipment
WHERE Status NOT IN (SELECT v FROM (VALUES ('LOST'), (NULL)) AS t(v));

SELECT COUNT(*) AS not_exists_rows
FROM demo.Shipment AS s
WHERE NOT EXISTS (SELECT 1 FROM (VALUES ('LOST'), (NULL)) AS t(v) WHERE t.v = s.Status);
GO

-- 2. ISNULL обрезает по типу первого аргумента, COALESCE — нет
DECLARE @short varchar(5) = NULL, @text nvarchar(100) = N'ул. Лесная';
SELECT ISNULL(@short, @text) AS isnull_result, COALESCE(@short, @text) AS coalesce_result;
GO

-- 3. Конфликт коллаций между tempdb и базой
SELECT CAST(SERVERPROPERTY('Collation') AS nvarchar(128)) AS instance_collation,
       CAST(DATABASEPROPERTYEX(N'Waybill', 'Collation') AS nvarchar(128)) AS database_collation;

DROP TABLE IF EXISTS #codes;
CREATE TABLE #codes (Code varchar(16));                  -- коллация tempdb
INSERT INTO #codes VALUES ('FASTEX');
BEGIN TRY
    -- Ошибка 468 — ошибка компиляции: в том же пакете TRY её не перехватит; динамический SQL компилируется отдельно
    EXEC sys.sp_executesql N'SELECT c.CarrierId FROM demo.Carrier AS c JOIN #codes AS t ON t.Code = c.Code;';
    PRINT 'Конфликта коллаций нет (коллации совпадают)';
END TRY
BEGIN CATCH
    PRINT CONCAT('Ошибка ', ERROR_NUMBER(), ': ', ERROR_MESSAGE());   -- 468 при разных коллациях экземпляра и базы
END CATCH;

DROP TABLE IF EXISTS #codes2;
CREATE TABLE #codes2 (Code varchar(16) COLLATE DATABASE_DEFAULT);   -- переносимый вариант
INSERT INTO #codes2 VALUES ('FASTEX');
SELECT c.CarrierId, c.Code FROM demo.Carrier AS c JOIN #codes2 AS t ON t.Code = c.Code;
DROP TABLE #codes;
DROP TABLE #codes2;
GO

-- 4. Трек-номера, отличающиеся только регистром (в CI-базе они «равны»)
SELECT TrackingNumber COLLATE Latin1_General_100_CI_AS AS tracking_ci, COUNT(*) AS variants
FROM (SELECT TrackingNumber FROM demo.Shipment
      UNION ALL SELECT LOWER(TrackingNumber) FROM demo.Shipment WHERE ShipmentId <= 3) AS x   -- искусственные дубли
GROUP BY TrackingNumber COLLATE Latin1_General_100_CI_AS
HAVING COUNT(DISTINCT TrackingNumber COLLATE Latin1_General_100_BIN2) > 1;
GO
