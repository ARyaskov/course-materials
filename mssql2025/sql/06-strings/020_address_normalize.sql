/*
  020_address_normalize.sql — функции нормализации и миграция ключей (урок 6.2). Идемпотентен.
  ship.fn_NormalizeTrackingNumber (regex-версия), crm.fn_NormalizePhone, ship.fn_NormalizeStreet;
  ship.Address.NormalizedKey → выражение через fn_NormalizeStreet; ship.Shipment.TrackingNumberNormalized → regex.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER FUNCTION ship.fn_NormalizeTrackingNumber (@TrackingNumber varchar(64))
RETURNS varchar(64)
WITH SCHEMABINDING
AS
BEGIN
    RETURN UPPER(REGEXP_REPLACE(@TrackingNumber, '[^A-Za-z0-9]', ''));
END;
GO

CREATE OR ALTER FUNCTION crm.fn_NormalizePhone (@Phone nvarchar(64), @DefaultCountryCode varchar(4))
RETURNS varchar(32)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @digits varchar(64) = REGEXP_REPLACE(@Phone, '[^0-9]', '');
    IF @digits IS NULL OR LEN(@digits) < 8 RETURN NULL;
    IF LEFT(@digits, 2) = '00' SET @digits = SUBSTRING(@digits, 3, 62);
    ELSE IF @DefaultCountryCode = '7' AND @Phone NOT LIKE '+%' AND LEN(@digits) = 11 AND LEFT(@digits, 1) = '8'
        SET @digits = '7' + SUBSTRING(@digits, 2, 10);
    ELSE IF @DefaultCountryCode = '7' AND @Phone NOT LIKE '+%' AND LEN(@digits) = 10
        SET @digits = '7' + @digits;
    ELSE IF @Phone NOT LIKE '+%' AND LEFT(@digits, 1) = '0' SET @digits = @DefaultCountryCode + SUBSTRING(@digits, 2, 62);
    ELSE IF @Phone NOT LIKE '+%' AND LEN(@digits) <= 10 SET @digits = @DefaultCountryCode + @digits;
    RETURN IIF(REGEXP_LIKE(@digits, '^[1-9][0-9]{7,14}$'), '+' + @digits, NULL);
END;
GO

CREATE OR ALTER FUNCTION ship.fn_NormalizeStreet (@Street nvarchar(200))
RETURNS nvarchar(200)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @s nvarchar(200) = LOWER(@Street);
    SET @s = REPLACE(@s, N'ё', N'е');
    -- Границы задаём через Unicode-классы: ASCII-граница \b не подходит для кириллицы.
    SET @s = REGEXP_REPLACE(@s, N'(^|[^\p{L}\p{N}])(ул\.?|улица)([^\p{L}\p{N}]|$)', N'\1ул\3');
    SET @s = REGEXP_REPLACE(@s, N'(^|[^\p{L}\p{N}])(пр-т|проспект)([^\p{L}\p{N}]|$)', N'\1пр\3');
    SET @s = REGEXP_REPLACE(@s, N'(^|[^\p{L}\p{N}])(пер\.?|переулок)([^\p{L}\p{N}]|$)', N'\1пер\3');
    SET @s = REGEXP_REPLACE(@s, N'[^\p{L}\p{N} ]', N' ');
    SET @s = REGEXP_REPLACE(@s, N'\s+', N' ');
    RETURN TRIM(@s);
END;
GO

-- Миграция ship.Address.NormalizedKey: новое выражение через fn_NormalizeStreet
IF EXISTS (SELECT 1 FROM sys.computed_columns WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'NormalizedKey'
           AND definition NOT LIKE '%fn_NormalizeStreet%')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'IX_Address_Merchant_NormalizedKey')
        DROP INDEX IX_Address_Merchant_NormalizedKey ON ship.Address;
    ALTER TABLE ship.Address DROP COLUMN NormalizedKey;
END;
GO
IF COL_LENGTH(N'ship.Address', N'NormalizedKey') IS NULL
    ALTER TABLE ship.Address ADD NormalizedKey AS CAST(CONCAT_WS('|', UPPER(CountryCode), REPLACE(REPLACE(PostalCode, ' ', ''), '-', ''),
                                                          ship.fn_NormalizeStreet(City), ship.fn_NormalizeStreet(Street), LOWER(Building)) AS nvarchar(400)) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Address') AND name = N'IX_Address_Merchant_NormalizedKey')
    CREATE NONCLUSTERED INDEX IX_Address_Merchant_NormalizedKey ON ship.Address (MerchantId, NormalizedKey);
GO

-- Миграция ship.Shipment.TrackingNumberNormalized: inline regex-выражение (без UDF — горячая таблица)
IF EXISTS (SELECT 1 FROM sys.computed_columns WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'TrackingNumberNormalized'
           AND definition NOT LIKE '%REGEXP_REPLACE%' AND definition NOT LIKE '%regexp_replace%')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_TrackingNumberNormalized')
        DROP INDEX IX_Shipment_TrackingNumberNormalized ON ship.Shipment;
    IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID(N'ship.Shipment') AND name = N'UQ_Shipment_Carrier_Tracking')
        ALTER TABLE ship.Shipment DROP CONSTRAINT UQ_Shipment_Carrier_Tracking;
    ALTER TABLE ship.Shipment DROP COLUMN TrackingNumberNormalized;
END;
GO
IF COL_LENGTH(N'ship.Shipment', N'TrackingNumberNormalized') IS NULL
    ALTER TABLE ship.Shipment ADD TrackingNumberNormalized AS CAST(UPPER(REGEXP_REPLACE(TrackingNumber, '[^A-Za-z0-9]', '')) AS varchar(64)) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID(N'ship.Shipment') AND name = N'UQ_Shipment_Carrier_Tracking')
    ALTER TABLE ship.Shipment ADD CONSTRAINT UQ_Shipment_Carrier_Tracking UNIQUE (CarrierId, TrackingNumberNormalized);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_TrackingNumberNormalized')
    CREATE NONCLUSTERED INDEX IX_Shipment_TrackingNumberNormalized
        ON ship.Shipment (TrackingNumberNormalized) INCLUDE (CarrierId, MerchantId, StatusId, PromisedAt, DeliveredAt);
GO

-- Проверки: два адреса Анна Иванова совпадают по ключу; детерминизм столбцов
SELECT AddressId, Street, NormalizedKey FROM ship.Address WHERE City IN (N'Москва', N'москва') ORDER BY NormalizedKey, AddressId;
SELECT OBJECT_NAME(c.object_id) AS table_name, c.name, c.is_persisted,
       COLUMNPROPERTY(c.object_id, c.name, 'IsDeterministic') AS is_deterministic, COLUMNPROPERTY(c.object_id, c.name, 'IsIndexable') AS is_indexable
FROM sys.computed_columns AS c WHERE c.name IN (N'NormalizedKey', N'TrackingNumberNormalized');
SELECT crm.fn_NormalizePhone(N'+7 (000) 000-01-01', '7') AS p1, crm.fn_NormalizePhone(N'8 (000) 000-01-01', '7') AS p2,
       crm.fn_NormalizePhone(N'007 000 000-01-01', '7') AS p3, crm.fn_NormalizePhone(N'12', '7') AS p4;
GO
