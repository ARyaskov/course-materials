/*
  030_ship.sql — ядро домена: адреса, отправления, события трекинга.
  ship.Address       — адреса отправителя/получателя (нормализация и дедупликация — глава 6)
  ship.Shipment      — отправление; уникально по (CarrierId, TrackingNumberNormalized)
  ship.TrackingEvent — поток событий от перевозчиков; уникально по (CarrierId, ExternalEventId)
                       (кластерный ключ начинается с OccurredAt — под секционирование в главе 10)
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ship.Address', N'U') IS NULL
BEGIN
    CREATE TABLE ship.Address
    (
        AddressId       bigint        NOT NULL IDENTITY(1, 1),
        MerchantId      int           NOT NULL,
        CountryCode     char(2)       NOT NULL,
        PostalCode      varchar(16)   NOT NULL,
        RegionId        smallint      NULL,
        City            nvarchar(100) NOT NULL,
        Street          nvarchar(200) NOT NULL,
        Building        nvarchar(32)  NOT NULL,
        Apartment       nvarchar(16)  NULL,
        RecipientName   nvarchar(200) NOT NULL,
        Phone           varchar(32)   NULL,
        -- Ключ грубой дедупликации: без регистра, пробелов и знаков (точную версию даёт глава 6)
        NormalizedKey   AS CAST(CONCAT_WS('|', UPPER(CountryCode), REPLACE(PostalCode, ' ', ''),
                                             UPPER(City), UPPER(Street), UPPER(Building)) AS nvarchar(400)) PERSISTED,   -- CAST: иначе REPLACE даёт nvarchar(4000) и ключ индекса > 1700 байт
        CreatedAt       datetime2(3)  NOT NULL CONSTRAINT DF_Address_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Address PRIMARY KEY CLUSTERED (AddressId),
        CONSTRAINT FK_Address_Merchant FOREIGN KEY (MerchantId) REFERENCES crm.Merchant (MerchantId),
        CONSTRAINT FK_Address_Region   FOREIGN KEY (RegionId)   REFERENCES ref.Region (RegionId),
        CONSTRAINT CK_Address_CountryCode CHECK (CountryCode = UPPER(CountryCode) AND LEN(CountryCode) = 2),
        CONSTRAINT CK_Address_Phone CHECK (Phone IS NULL OR REGEXP_LIKE(Phone, '^\+[1-9][0-9]{7,14}$'))
    );
END;
GO

IF OBJECT_ID(N'ship.Shipment', N'U') IS NULL
BEGIN
    CREATE TABLE ship.Shipment
    (
        ShipmentId               bigint        NOT NULL IDENTITY(1, 1),
        MerchantId               int           NOT NULL,
        CarrierId                smallint      NOT NULL,
        TrackingNumber           varchar(64)   NOT NULL,
        TrackingNumberNormalized AS CAST(UPPER(REPLACE(REPLACE(TrackingNumber, ' ', ''), '-', '')) AS varchar(64)) PERSISTED,   -- CAST: REPLACE возвращает varchar(8000)
        ExternalOrderId          nvarchar(64)  NOT NULL,       -- номер заказа в системе магазина
        StatusId                 tinyint       NOT NULL,
        OriginAddressId          bigint        NOT NULL,
        DestinationAddressId     bigint        NOT NULL,
        DeclaredValue            decimal(19, 4) NOT NULL CONSTRAINT DF_Shipment_DeclaredValue DEFAULT (0),
        WeightGrams              int           NOT NULL,
        CreatedAt                datetime2(3)  NOT NULL CONSTRAINT DF_Shipment_CreatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedAt                datetime2(3)  NOT NULL CONSTRAINT DF_Shipment_UpdatedAt DEFAULT SYSUTCDATETIME(),
        PromisedAt               datetime2(3)  NULL,           -- обещанный срок доставки (SLA)
        DeliveredAt              datetime2(3)  NULL,
        LastEventAt              datetime2(3)  NULL,
        CONSTRAINT PK_Shipment PRIMARY KEY CLUSTERED (ShipmentId),
        CONSTRAINT UQ_Shipment_Carrier_Tracking UNIQUE (CarrierId, TrackingNumberNormalized),
        CONSTRAINT UQ_Shipment_Merchant_Order   UNIQUE (MerchantId, ExternalOrderId),
        CONSTRAINT FK_Shipment_Merchant FOREIGN KEY (MerchantId) REFERENCES crm.Merchant (MerchantId),
        CONSTRAINT FK_Shipment_Carrier  FOREIGN KEY (CarrierId)  REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT FK_Shipment_Status   FOREIGN KEY (StatusId)   REFERENCES ref.ShipmentStatus (StatusId),
        CONSTRAINT FK_Shipment_OriginAddress      FOREIGN KEY (OriginAddressId)      REFERENCES ship.Address (AddressId),
        CONSTRAINT FK_Shipment_DestinationAddress FOREIGN KEY (DestinationAddressId) REFERENCES ship.Address (AddressId),
        CONSTRAINT CK_Shipment_TrackingNumber CHECK (REGEXP_LIKE(TrackingNumber, '^[A-Za-z0-9 -]{8,64}$')),
        CONSTRAINT CK_Shipment_Weight CHECK (WeightGrams BETWEEN 1 AND 1000000),
        CONSTRAINT CK_Shipment_DeclaredValue CHECK (DeclaredValue >= 0),
        CONSTRAINT CK_Shipment_Delivered CHECK (DeliveredAt IS NULL OR DeliveredAt >= CreatedAt)
    );
END;
GO

IF OBJECT_ID(N'ship.TrackingEvent', N'U') IS NULL
BEGIN
    CREATE TABLE ship.TrackingEvent
    (
        EventId             bigint        NOT NULL IDENTITY(1, 1),
        ShipmentId          bigint        NOT NULL,
        CarrierId           smallint      NOT NULL,
        ExternalEventId     varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,  -- ключ идемпотентности
        StatusId            tinyint       NOT NULL,
        OccurredAt          datetime2(3)  NOT NULL,       -- время события по данным перевозчика (UTC)
        ReceivedAt          datetime2(3)  NOT NULL CONSTRAINT DF_TrackingEvent_ReceivedAt DEFAULT SYSUTCDATETIME(),
        LocationText        nvarchar(200) NULL,
        LocationPostalCode  varchar(16)   NULL,
        Description         nvarchar(400) NULL,
        CONSTRAINT PK_TrackingEvent PRIMARY KEY CLUSTERED (OccurredAt, EventId) ON FG_Events,
        CONSTRAINT UQ_TrackingEvent_Carrier_External UNIQUE NONCLUSTERED (CarrierId, ExternalEventId) ON FG_Events,
        CONSTRAINT FK_TrackingEvent_Shipment FOREIGN KEY (ShipmentId) REFERENCES ship.Shipment (ShipmentId),
        CONSTRAINT FK_TrackingEvent_Carrier  FOREIGN KEY (CarrierId)  REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT FK_TrackingEvent_Status   FOREIGN KEY (StatusId)   REFERENCES ref.ShipmentStatus (StatusId),
        CONSTRAINT CK_TrackingEvent_OccurredAt CHECK (OccurredAt >= '2020-01-01' AND OccurredAt < '2100-01-01')
    ) ON FG_Events;
END;
GO
