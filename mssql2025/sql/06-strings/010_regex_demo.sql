-- diagnostic: safe to re-run
/*
  010_regex_demo.sql — REGEXP_LIKE: проверка трек-номеров по шаблонам перевозчиков, валидация шаблонов, флаги (урок 6.1).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- 1. Соответствие трек-номеров шаблону своего перевозчика
SELECT c.Code, c.TrackingNumberPattern,
       SUM(IIF(REGEXP_LIKE(s.TrackingNumberNormalized, c.TrackingNumberPattern), 1, 0)) AS matching,
       SUM(IIF(REGEXP_LIKE(s.TrackingNumberNormalized, c.TrackingNumberPattern), 0, 1)) AS violating
FROM ref.Carrier AS c
LEFT JOIN ship.Shipment AS s ON s.CarrierId = c.CarrierId
GROUP BY c.Code, c.TrackingNumberPattern;
-- CITYRUN: шаблон '^CR-[0-9]{4}-[0-9]{6}$' проверяется по исходному TrackingNumber (с дефисами), нормализованный их не содержит:
SELECT c.Code, s.TrackingNumber, IIF(REGEXP_LIKE(s.TrackingNumber, c.TrackingNumberPattern), 1, 0) AS raw_matches   -- предикат: в списке SELECT только через IIF/CASE
FROM ship.Shipment AS s JOIN ref.Carrier AS c ON c.CarrierId = s.CarrierId;

-- 2. Валидация шаблонов справочника (невалидный regex → ошибка выполнения)
DECLARE @code varchar(16), @pattern varchar(200), @probe bit;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT Code, TrackingNumberPattern FROM ref.Carrier;
OPEN cur; FETCH NEXT FROM cur INTO @code, @pattern;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @probe = IIF(REGEXP_LIKE('probe', @pattern), 1, 0);   -- сам вызов и есть проверка синтаксиса
        PRINT CONCAT(@code, ': valid pattern');
    END TRY
    BEGIN CATCH
        PRINT CONCAT(@code, ': INVALID - ', ERROR_MESSAGE());
    END CATCH;
    FETCH NEXT FROM cur INTO @code, @pattern;
END;
CLOSE cur; DEALLOCATE cur;
GO

-- 3. Флаги
SELECT IIF(REGEXP_LIKE('fx0000000001', '^FX[0-9]{10}$', 'i'), 1, 0) AS flag_i,
       IIF(REGEXP_LIKE('fx0000000001', '^FX[0-9]{10}$', 'c'), 1, 0) AS flag_c,
       IIF(REGEXP_LIKE(N'line1' + NCHAR(10) + N'FX0000000001', '^FX', 'm'), 1, 0) AS flag_m,
       IIF(REGEXP_LIKE(N'a' + NCHAR(10) + N'b', '^a.b$', 's'), 1, 0) AS flag_s;
GO

-- 4. SARGable-префикс + regex как residual (на demo.Shipment)
SET STATISTICS IO ON;
SELECT COUNT(*) FROM demo.Shipment WHERE REGEXP_LIKE(TrackingNumber, '^DM0{6}[0-9]{4}$');
SELECT COUNT(*) FROM demo.Shipment WHERE TrackingNumber LIKE 'DM000000%' AND REGEXP_LIKE(TrackingNumber, '^DM0{6}[0-9]{4}$');
SET STATISTICS IO OFF;
GO
