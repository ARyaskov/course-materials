/*
  010_ref.sql — справочники схемы ref.
  ref.Carrier        — перевозчики (код, формат webhook, regex трек-номера)
  ref.Region         — регионы доставки
  ref.ShipmentStatus — словарь статусов отправления
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ref.Carrier', N'U') IS NULL
BEGIN
    CREATE TABLE ref.Carrier
    (
        CarrierId               smallint      NOT NULL IDENTITY(1, 1),
        Code                    varchar(16)   COLLATE Latin1_General_100_BIN2 NOT NULL,
        Name                    nvarchar(100) NOT NULL,
        WebhookFormat           varchar(20)   NOT NULL,          -- 'array' | 'nested' | 'flat'
        TrackingNumberPattern   varchar(200)  NOT NULL,          -- regex для REGEXP_LIKE (глава 6)
        SlaHoursDefault         smallint      NOT NULL,
        IsActive                bit           NOT NULL CONSTRAINT DF_Carrier_IsActive DEFAULT (1),
        CreatedAt               datetime2(3)  NOT NULL CONSTRAINT DF_Carrier_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Carrier PRIMARY KEY CLUSTERED (CarrierId),
        CONSTRAINT UQ_Carrier_Code UNIQUE (Code),
        CONSTRAINT CK_Carrier_Code CHECK (Code = UPPER(Code) AND LEN(Code) BETWEEN 3 AND 16),
        CONSTRAINT CK_Carrier_WebhookFormat CHECK (WebhookFormat IN ('array', 'nested', 'flat')),
        CONSTRAINT CK_Carrier_SlaHours CHECK (SlaHoursDefault BETWEEN 1 AND 24 * 60)
    );
END;
GO

IF OBJECT_ID(N'ref.Region', N'U') IS NULL
BEGIN
    CREATE TABLE ref.Region
    (
        RegionId    smallint      NOT NULL IDENTITY(1, 1),
        Code        varchar(8)    COLLATE Latin1_General_100_BIN2 NOT NULL,
        Name        nvarchar(100) NOT NULL,
        CountryCode char(2)       NOT NULL,
        TimeZone    nvarchar(64)  NOT NULL,   -- имя из sys.time_zone_info, для AT TIME ZONE
        CONSTRAINT PK_Region PRIMARY KEY CLUSTERED (RegionId),
        CONSTRAINT UQ_Region_Code UNIQUE (Code)
    );
END;
GO

IF OBJECT_ID(N'ref.ShipmentStatus', N'U') IS NULL
BEGIN
    CREATE TABLE ref.ShipmentStatus
    (
        StatusId    tinyint      NOT NULL,     -- значения задаются явно: это словарь, а не счётчик
        Code        varchar(32)  COLLATE Latin1_General_100_BIN2 NOT NULL,
        Name        nvarchar(100) NOT NULL,
        IsTerminal  bit          NOT NULL,
        SortOrder   tinyint      NOT NULL,
        CONSTRAINT PK_ShipmentStatus PRIMARY KEY CLUSTERED (StatusId),
        CONSTRAINT UQ_ShipmentStatus_Code UNIQUE (Code)
    );
END;
GO
