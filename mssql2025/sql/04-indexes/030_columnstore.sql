/*
  030_columnstore.sql — некластерный columnstore на потоке событий и витрина analytics.CarrierSla (урок 4.6). Идемпотентен.
  NCCI без COMPRESSION_DELAY: ship.TrackingEvent — append-only.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'ship.TrackingEvent') AND name = N'NCCI_TrackingEvent')
    CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_TrackingEvent
        ON ship.TrackingEvent (ShipmentId, CarrierId, StatusId, OccurredAt, LocationPostalCode)
        ON FG_Events;
GO

IF OBJECT_ID(N'analytics.CarrierSla', N'U') IS NULL
BEGIN
    CREATE TABLE analytics.CarrierSla
    (
        CarrierId       smallint      NOT NULL,
        RegionId        smallint      NULL,
        PeriodStart     date          NOT NULL,
        Shipments       int           NOT NULL,
        Delivered       int           NOT NULL,
        Late            int           NOT NULL,
        MedianHours     decimal(8, 1) NULL,
        P95Hours        decimal(8, 1) NULL,
        RefreshedAt     datetime2(3)  NOT NULL CONSTRAINT DF_CarrierSla_RefreshedAt DEFAULT SYSUTCDATETIME(),
        INDEX CCI_CarrierSla CLUSTERED COLUMNSTORE
    );
END;
GO
