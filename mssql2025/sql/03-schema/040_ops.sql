/*
  040_ops.sql — операционные таблицы схемы ops.
  ops.Incident — инциденты по отправлениям (описание, серьёзность; embedding — глава 14)
  ops.Outbox   — transactional outbox: события для внешних потребителей (dequeue — глава 8, диспетчер — глава 13)
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.Incident', N'U') IS NULL
BEGIN
    CREATE TABLE ops.Incident
    (
        IncidentId      bigint        NOT NULL IDENTITY(1, 1),
        ShipmentId      bigint        NULL,
        MerchantId      int           NOT NULL,
        CarrierId       smallint      NULL,
        Title           nvarchar(200) NOT NULL,
        Description     nvarchar(max) NOT NULL,
        Severity        tinyint       NOT NULL,        -- 1 low … 4 critical
        IsResolved      bit           NOT NULL CONSTRAINT DF_Incident_IsResolved DEFAULT (0),
        CreatedAt       datetime2(3)  NOT NULL CONSTRAINT DF_Incident_CreatedAt DEFAULT SYSUTCDATETIME(),
        ResolvedAt      datetime2(3)  NULL,
        CONSTRAINT PK_Incident PRIMARY KEY CLUSTERED (IncidentId),
        CONSTRAINT FK_Incident_Shipment FOREIGN KEY (ShipmentId) REFERENCES ship.Shipment (ShipmentId),
        CONSTRAINT FK_Incident_Merchant FOREIGN KEY (MerchantId) REFERENCES crm.Merchant (MerchantId),
        CONSTRAINT FK_Incident_Carrier  FOREIGN KEY (CarrierId)  REFERENCES ref.Carrier (CarrierId),
        CONSTRAINT CK_Incident_Severity CHECK (Severity BETWEEN 1 AND 4),
        CONSTRAINT CK_Incident_Resolved CHECK ((IsResolved = 0 AND ResolvedAt IS NULL) OR (IsResolved = 1 AND ResolvedAt IS NOT NULL))
    );
END;
GO

IF OBJECT_ID(N'ops.Outbox', N'U') IS NULL
BEGIN
    CREATE TABLE ops.Outbox
    (
        OutboxId        bigint        NOT NULL IDENTITY(1, 1),
        Topic           varchar(64)   COLLATE Latin1_General_100_BIN2 NOT NULL,   -- 'shipment.status-changed', ...
        AggregateType   varchar(32)   NOT NULL,
        AggregateId     bigint        NOT NULL,
        Payload         nvarchar(max) NOT NULL,        -- станет json в главе 5
        CreatedAt       datetime2(3)  NOT NULL CONSTRAINT DF_Outbox_CreatedAt DEFAULT SYSUTCDATETIME(),
        LockedUntil     datetime2(3)  NULL,            -- аренда воркера (глава 8/13)
        Attempts        tinyint       NOT NULL CONSTRAINT DF_Outbox_Attempts DEFAULT (0),
        ProcessedAt     datetime2(3)  NULL,
        LastError       nvarchar(1000) NULL,
        CONSTRAINT PK_Outbox PRIMARY KEY CLUSTERED (OutboxId),
        CONSTRAINT CK_Outbox_Payload CHECK (ISJSON(Payload) = 1)
    );
END;
GO
