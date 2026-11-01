/*
  060_json_indexes.sql — индексирование полей JSON (урок 5.7). Идемпотентен.
  1) вычисляемые столбцы из Attributes + фильтрованные индексы (рабочий путь);
  2) JSON-индекс SQL Server 2025 (preview в RTM) — попытка создания в TRY/CATCH, результат печатается.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'ship.Shipment', N'IsFragile') IS NULL
    ALTER TABLE ship.Shipment ADD IsFragile AS CAST(JSON_VALUE(Attributes, '$.fragile') AS bit);
GO
IF COL_LENGTH(N'ship.Shipment', N'SignatureRequired') IS NULL
    ALTER TABLE ship.Shipment ADD SignatureRequired AS CAST(IIF(JSON_VALUE(Attributes, '$.signature') = 'required', 1, 0) AS bit);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Fragile_Active')
    CREATE NONCLUSTERED INDEX IX_Shipment_Fragile_Active
        ON ship.Shipment (IsFragile, CarrierId, PromisedAt)   -- вычисляемый столбец — ведущий ключ; в WHERE фильтрованного индекса он недопустим (10609)
        INCLUDE (TrackingNumber)
        WHERE DeliveredAt IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'IX_Shipment_Signature_Active')
    CREATE NONCLUSTERED INDEX IX_Shipment_Signature_Active
        ON ship.Shipment (SignatureRequired, MerchantId, PromisedAt)
        INCLUDE (TrackingNumber)
        WHERE DeliveredAt IS NULL;
GO

-- JSON-индекс: preview в RTM SQL Server 2025. Синтаксис и требования сверьте с документацией вашей сборки/CU.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'JIX_Shipment_Attributes')
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql N'CREATE JSON INDEX JIX_Shipment_Attributes ON ship.Shipment (Attributes) FOR (''$'');';
        PRINT 'JIX_Shipment_Attributes: created';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('JIX_Shipment_Attributes: unavailable on this build (', ERROR_NUMBER(), ' ', ERROR_MESSAGE(), ')');
    END CATCH;
END;
GO

SELECT name, type_desc, filter_definition FROM sys.indexes
WHERE object_id = OBJECT_ID(N'ship.Shipment') AND (name LIKE 'IX_Shipment_%Active' OR name LIKE 'JIX%');
GO
