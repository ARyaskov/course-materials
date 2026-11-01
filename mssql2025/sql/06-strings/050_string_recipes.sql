/*
  050_string_recipes.sql — строковые рецепты (урок 6.7): ship.fn_FormatAddressLine, ops.fn_UtcIso, маскирование, FORMAT vs CONVERT, хэши.
  Функции создаются идемпотентно; демонстрации — только чтение.
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER FUNCTION ship.fn_FormatAddressLine (@AddressId bigint)
RETURNS nvarchar(600)
-- без SCHEMABINDING: привязка к схеме запретила бы ALTER COLUMN на ship.Address (маски DDM в главе 15, ошибка 5074)
AS
BEGIN
    DECLARE @line nvarchar(600);
    SELECT @line = CONCAT_WS(N', ', a.RecipientName, a.Street + N' ' + a.Building,
                             IIF(a.Apartment IS NULL, NULL, N'кв. ' + a.Apartment),
                             a.PostalCode + N' ' + a.City, r.Name, a.CountryCode)
    FROM ship.Address AS a
    LEFT JOIN ref.Region AS r ON r.RegionId = a.RegionId
    WHERE a.AddressId = @AddressId;
    RETURN @line;
END;
GO

CREATE OR ALTER FUNCTION ops.fn_UtcIso (@t datetime2(3))
RETURNS varchar(24)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN @t IS NULL THEN NULL ELSE CONVERT(varchar(23), @t, 126) + 'Z' END;
END;
GO

-- 1. Адресные строки
SELECT AddressId, ship.fn_FormatAddressLine(AddressId) AS address_line FROM ship.Address;

-- 2. Маскирование трек-номеров: STUFF и REGEXP_REPLACE с группами
SELECT TrackingNumber,
       STUFF(TrackingNumber, 3, LEN(TrackingNumber) - 6, REPLICATE('*', LEN(TrackingNumber) - 6)) AS masked_stuff,
       REGEXP_REPLACE(TrackingNumber, '^(..).*(....)$', '\1****\2') AS masked_regex
FROM ship.Shipment;

-- 3. FORMAT против CONVERT против диапазона
SET STATISTICS TIME ON;
SELECT COUNT(*) FROM demo.Shipment WHERE FORMAT(CreatedAt, 'yyyy-MM') = '2026-08';
SELECT COUNT(*) FROM demo.Shipment WHERE CONVERT(char(7), CreatedAt, 126) = '2026-08';
SELECT COUNT(*) FROM demo.Shipment WHERE CreatedAt >= '2026-08-01' AND CreatedAt < '2026-09-01';
SET STATISTICS TIME OFF;

-- 4. Хэши тел webhook (по строкам, без файлов): base64 и hex
SELECT BASE64_ENCODE(HASHBYTES('SHA2_256', N'{"tracking_no":"CR-2026-000042","state":"DELIVERED"}')) AS hash_b64,
       CONVERT(varchar(64), HASHBYTES('SHA2_256', N'{"tracking_no":"CR-2026-000042","state":"DELIVERED"}'), 2) AS hash_hex;

-- 5. UNISTR и длины в UTF-8/UTF-16
SELECT city, LEN(city) AS chars, DATALENGTH(city) AS utf16_bytes, DATALENGTH(CAST(city AS varchar(100))) AS utf8_bytes
FROM (VALUES (UNISTR(N'Моск\0432\0430')), (UNISTR(N'Ор\0451л')), (UNISTR(N'Каза\043D\044C'))) AS t(city);
GO
