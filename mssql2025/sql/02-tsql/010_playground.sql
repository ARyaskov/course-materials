/*
  010_playground.sql — полигон главы 2: схема demo с упрощёнными отправлениями и событиями.
  Настоящие таблицы ship.* появятся в главе 3; demo.* нужны, чтобы отрабатывать синтаксис T-SQL
  на данных с правдоподобной формой (перевозчики, статусы, время доставки).
  Идемпотентен. Генерирует 2 000 отправлений и ~7 000 событий через GENERATE_SERIES.
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID(N'demo') IS NULL
    EXEC(N'CREATE SCHEMA demo AUTHORIZATION dbo;');
GO

IF OBJECT_ID(N'demo.Ping', N'U') IS NULL
    CREATE TABLE demo.Ping (PingId int NOT NULL IDENTITY PRIMARY KEY, At datetime2(3) NOT NULL);
GO

CREATE OR ALTER PROCEDURE demo.usp_Ping
    @Message nvarchar(100) = N'pong'
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @Message AS Message, SYSUTCDATETIME() AS At;
END;
GO

IF OBJECT_ID(N'demo.Carrier', N'U') IS NULL
BEGIN
    CREATE TABLE demo.Carrier
    (
        CarrierId   smallint     NOT NULL PRIMARY KEY,
        Code        varchar(16)  NOT NULL UNIQUE,
        SlaHours    smallint     NOT NULL
    );
    INSERT INTO demo.Carrier (CarrierId, Code, SlaHours)
    VALUES (1, 'FASTEX', 48), (2, 'NORDPOST', 96), (3, 'CITYRUN', 24);
END;
GO

IF OBJECT_ID(N'demo.Shipment', N'U') IS NULL
BEGIN
    CREATE TABLE demo.Shipment
    (
        ShipmentId      bigint        NOT NULL IDENTITY(1, 1) PRIMARY KEY,
        MerchantId      int           NOT NULL,
        CarrierId       smallint      NOT NULL REFERENCES demo.Carrier (CarrierId),
        TrackingNumber  varchar(64)   NOT NULL,
        Status          varchar(32)   NOT NULL,
        City            nvarchar(100) NOT NULL,
        WeightGrams     int           NOT NULL,
        DeclaredValue   decimal(19, 4) NOT NULL,
        CreatedAt       datetime2(3)  NOT NULL,
        PromisedAt      datetime2(3)  NOT NULL,
        DeliveredAt     datetime2(3)  NULL
    );

    -- 2 000 отправлений за 90 дней; детерминированные «случайности» через CHECKSUM(NEWID())
    ;WITH n AS (SELECT value AS i FROM GENERATE_SERIES(1, 2000))
    INSERT INTO demo.Shipment (MerchantId, CarrierId, TrackingNumber, Status, City, WeightGrams, DeclaredValue, CreatedAt, PromisedAt, DeliveredAt)
    SELECT
        1 + i % 3                                                        AS MerchantId,
        1 + i % 3                                                        AS CarrierId,
        CONCAT('DM', RIGHT(CONCAT('0000000000', i), 10))                 AS TrackingNumber,
        CASE WHEN i % 10 = 0 THEN 'IN_TRANSIT' WHEN i % 17 = 0 THEN 'RETURNED' WHEN i % 23 = 0 THEN 'LOST' ELSE 'DELIVERED' END,
        CHOOSE(1 + i % 5, N'Москва', N'Санкт-Петербург', N'Екатеринбург', N'Новосибирск', N'Казань') AS City,
        100 + ABS(CHECKSUM(NEWID())) % 20000                             AS WeightGrams,
        CAST(5 + ABS(CHECKSUM(NEWID())) % 500 AS decimal(19, 4))         AS DeclaredValue,
        x.CreatedAt,
        DATEADD(HOUR, 72, x.CreatedAt) AS PromisedAt,   -- временно: точный SLA перевозчика проставит UPDATE ниже
        NULL AS DeliveredAt
    FROM n
    CROSS APPLY (SELECT DATEADD(MINUTE, -ABS(CHECKSUM(NEWID())) % (90 * 24 * 60), CAST('2026-09-15T00:00:00' AS datetime2(3))) AS CreatedAt) AS x;

    UPDATE s
    SET PromisedAt  = DATEADD(HOUR, c.SlaHours, s.CreatedAt),
        DeliveredAt = CASE WHEN s.Status IN ('DELIVERED', 'RETURNED')
                           THEN DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % (c.SlaHours * 90), s.CreatedAt)   -- иногда позже SLA
                           ELSE NULL END
    FROM demo.Shipment AS s
    JOIN demo.Carrier AS c ON c.CarrierId = s.CarrierId;
END;
GO

IF OBJECT_ID(N'demo.TrackingEvent', N'U') IS NULL
BEGIN
    CREATE TABLE demo.TrackingEvent
    (
        EventId     bigint        NOT NULL IDENTITY(1, 1) PRIMARY KEY,
        ShipmentId  bigint        NOT NULL REFERENCES demo.Shipment (ShipmentId),
        Status      varchar(32)   NOT NULL,
        OccurredAt  datetime2(3)  NOT NULL,
        Location    nvarchar(100) NULL,
        Note        nvarchar(200) NULL
    );

    -- 2–5 событий на отправление в хронологическом порядке
    INSERT INTO demo.TrackingEvent (ShipmentId, Status, OccurredAt, Location, Note)
    SELECT s.ShipmentId,
           CHOOSE(e.value, 'ACCEPTED', 'IN_TRANSIT', 'AT_HUB', 'OUT_FOR_DELIVERY', 'DELIVERED') AS Status,
           DATEADD(MINUTE, e.value * 300 + ABS(CHECKSUM(NEWID())) % 120, s.CreatedAt) AS OccurredAt,
           s.City,
           CASE WHEN e.value = 5 THEN N'Signed by recipient' END
    FROM demo.Shipment AS s
    CROSS APPLY GENERATE_SERIES(CAST(1 AS bigint), 2 + s.ShipmentId % 4) AS e   -- аргументы одного типа: ShipmentId bigint
    WHERE e.value <= 5;

    CREATE INDEX IX_TrackingEvent_Shipment ON demo.TrackingEvent (ShipmentId, OccurredAt);
END;
GO
