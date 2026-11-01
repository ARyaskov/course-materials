/*
  065_computed_columns.sql — вычисляемые столбцы и функция нормализации трек-номера (урок 3.6). Идемпотентен.
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
    RETURN UPPER(REPLACE(REPLACE(@TrackingNumber, ' ', ''), '-', ''));
END;
GO

IF COL_LENGTH(N'ship.Shipment', N'WeightClass') IS NULL
    ALTER TABLE ship.Shipment ADD WeightClass AS
        CASE WHEN WeightGrams < 1000 THEN 'S' WHEN WeightGrams < 10000 THEN 'M' ELSE 'L' END PERSISTED;
GO

IF COL_LENGTH(N'ship.Address', N'PostalCodeNormalized') IS NULL
    ALTER TABLE ship.Address ADD PostalCodeNormalized AS REPLACE(REPLACE(PostalCode, ' ', ''), '-', '') PERSISTED;
GO

IF COL_LENGTH(N'ship.TrackingEvent', N'OccurredDate') IS NULL
    ALTER TABLE ship.TrackingEvent ADD OccurredDate AS CAST(OccurredAt AS date);   -- не PERSISTED: детерминирован и индексируем
GO

-- Контроль детерминизма/индексируемости
SELECT OBJECT_NAME(c.object_id) AS table_name, c.name, c.is_persisted,
       COLUMNPROPERTY(c.object_id, c.name, 'IsDeterministic') AS is_deterministic,
       COLUMNPROPERTY(c.object_id, c.name, 'IsPrecise') AS is_precise,
       COLUMNPROPERTY(c.object_id, c.name, 'IsIndexable') AS is_indexable
FROM sys.computed_columns AS c
WHERE c.object_id IN (OBJECT_ID(N'ship.Shipment'), OBJECT_ID(N'ship.Address'), OBJECT_ID(N'ship.TrackingEvent'));
GO
