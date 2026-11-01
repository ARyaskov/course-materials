/*
  030_fuzzy_dedup.sql — нечёткая дедупликация адресов (урок 6.5). Идемпотентен.
  Индекс под блокирующий ключ, ship.usp_FindSimilarAddress, ship.usp_ReportAddressDuplicates.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
-- Функции нечёткого сравнения в SQL Server 2025 — preview: без PREVIEW_FEATURES = ON они «не распознаются» (ошибка 195)
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'IX_Address_Merchant_Postal_Building')
    CREATE NONCLUSTERED INDEX IX_Address_Merchant_Postal_Building
        ON ship.Address (MerchantId, CountryCode, PostalCodeNormalized, Building)
        INCLUDE (Street, City, RecipientName);
GO

CREATE OR ALTER PROCEDURE ship.usp_FindSimilarAddress
    @MerchantId int, @CountryCode char(2), @PostalCode varchar(16), @City nvarchar(100), @Street nvarchar(200), @Building nvarchar(32),
    @MinSimilarity int = 92
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @streetNorm nvarchar(200) = ship.fn_NormalizeStreet(@Street);
    DECLARE @postalNorm varchar(16) = REPLACE(REPLACE(@PostalCode, ' ', ''), '-', '');

    SELECT TOP (5) a.AddressId, a.Street, a.Building, a.City, a.RecipientName,
           JARO_WINKLER_SIMILARITY(ship.fn_NormalizeStreet(a.Street), @streetNorm) AS similarity,
           EDIT_DISTANCE(ship.fn_NormalizeStreet(a.Street), @streetNorm) AS edit_distance
    FROM ship.Address AS a
    WHERE a.MerchantId = @MerchantId AND a.CountryCode = UPPER(@CountryCode)
      AND a.PostalCodeNormalized = @postalNorm AND LOWER(a.Building) = LOWER(@Building)
      AND JARO_WINKLER_SIMILARITY(ship.fn_NormalizeStreet(a.Street), @streetNorm) >= @MinSimilarity
    ORDER BY similarity DESC, edit_distance;
END;
GO

CREATE OR ALTER PROCEDURE ship.usp_ReportAddressDuplicates
    @MinSimilarity int = 92,
    @MaxEditDistance int = 3
AS
BEGIN
    SET NOCOUNT ON;
    WITH addr AS
    (
        SELECT AddressId, MerchantId, CountryCode, PostalCodeNormalized, LOWER(Building) AS Building,
               ship.fn_NormalizeStreet(Street) AS StreetNorm, RecipientName
        FROM ship.Address
    )
    SELECT a.MerchantId, a.AddressId AS address_a, b.AddressId AS address_b, a.StreetNorm AS street_a, b.StreetNorm AS street_b,
           EDIT_DISTANCE(a.StreetNorm, b.StreetNorm) AS edit_distance,
           JARO_WINKLER_SIMILARITY(a.StreetNorm, b.StreetNorm) AS jw_similarity,
           JARO_WINKLER_SIMILARITY(LOWER(a.RecipientName), LOWER(b.RecipientName)) AS recipient_similarity
    FROM addr AS a
    JOIN addr AS b
      ON b.MerchantId = a.MerchantId AND b.CountryCode = a.CountryCode
     AND b.PostalCodeNormalized = a.PostalCodeNormalized AND b.Building = a.Building
     AND b.AddressId > a.AddressId
    WHERE a.StreetNorm <> b.StreetNorm
      AND JARO_WINKLER_SIMILARITY(a.StreetNorm, b.StreetNorm) >= @MinSimilarity
      AND EDIT_DISTANCE(a.StreetNorm, b.StreetNorm) <= @MaxEditDistance
    ORDER BY jw_similarity DESC;
END;
GO

-- Проверка на seed: точные дубли (после нормализации) и нечёткие кандидаты
SELECT NormalizedKey, COUNT(*) AS addresses, STRING_AGG(CAST(AddressId AS varchar(10)), ',') AS ids
FROM ship.Address GROUP BY NormalizedKey HAVING COUNT(*) > 1;
EXEC ship.usp_FindSimilarAddress @MerchantId = 1, @CountryCode = 'RU', @PostalCode = '127018', @City = N'Москва', @Street = N'ул. Леснаа', @Building = N'80';
EXEC ship.usp_ReportAddressDuplicates;
GO
