/*
  010_json_columns.sql — нативный json в Waybill (урок 5.1). Идемпотентен.
  Новые столбцы: ship.TrackingEvent.RawPayload, ship.Shipment.Attributes, crm.Merchant.Settings.
  ops.Outbox.Payload: nvarchar(max) + CHECK(ISJSON) → json.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'ship.TrackingEvent', N'RawPayload') IS NULL
    ALTER TABLE ship.TrackingEvent ADD RawPayload json NULL;
GO
IF COL_LENGTH(N'ship.Shipment', N'Attributes') IS NULL
    ALTER TABLE ship.Shipment ADD Attributes json NULL;
GO
IF COL_LENGTH(N'crm.Merchant', N'Settings') IS NULL
    ALTER TABLE crm.Merchant ADD Settings json NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns AS c JOIN sys.types AS t ON t.user_type_id = c.user_type_id
           WHERE c.object_id = OBJECT_ID(N'ops.Outbox') AND c.name = N'Payload' AND t.name = N'nvarchar')
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Outbox_Payload')
        ALTER TABLE ops.Outbox DROP CONSTRAINT CK_Outbox_Payload;
    ALTER TABLE ops.Outbox ALTER COLUMN Payload json NOT NULL;
END;
GO

SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS table_name, c.name AS column_name, t.name AS type_name
FROM sys.columns AS c JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE t.name = N'json' AND OBJECTPROPERTY(c.object_id, 'IsUserTable') = 1;
GO
