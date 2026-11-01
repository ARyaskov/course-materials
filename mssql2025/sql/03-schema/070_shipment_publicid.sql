/*
  070_shipment_publicid.sql — внешний идентификатор отправления для API (урок 3.2, 3.8). Идемпотентен, в транзакции.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

IF COL_LENGTH(N'ship.Shipment', N'PublicId') IS NULL
    ALTER TABLE ship.Shipment ADD PublicId uniqueidentifier NOT NULL
        CONSTRAINT DF_Shipment_PublicId DEFAULT NEWSEQUENTIALID();

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.Shipment') AND name = N'UQ_Shipment_PublicId')
    ALTER TABLE ship.Shipment ADD CONSTRAINT UQ_Shipment_PublicId UNIQUE NONCLUSTERED (PublicId);

COMMIT;
GO
